# Credential rotation runbook

**Status: PLANNING ONLY. Nothing in this document has been executed.**

Prepared in response to the production secret exposure described in
[production_secret_safety.md](production_secret_safety.md). Five credential
categories were disclosed into AI-visible terminal history and must be treated
as compromised:

1. OpenAI API credential
2. AWS access credentials
3. Brevo SMTP credential
4. PostgreSQL / `DATABASE_URL` credential
5. `SECRET_KEY_BASE`

**Rotation — not history rewriting — is the remediation.** Shell history, chat
history, git history and Heroku release history are not reliable containment
boundaries, and attempting to scrub them tends to re-expose the value. Assume
disclosure is permanent and invalidate the credentials.

Every step below requires **explicit human authorization in the current turn**.
An AI agent must not execute any of it on its own initiative, and must never
place a credential value in terminal output, a commit, or a PR description.

---

## Environment facts this plan depends on

| Fact | Value | Source |
| --- | --- | --- |
| App | `evening-anchorage-70843` | `heroku info` |
| Formation | `web=1:Basic` (Puma only), `worker=1:Basic` (Solid Queue only) | `heroku ps:scale` |
| Rails / Ruby | 8.0.1 / 3.2.3 | `Gemfile.lock` |
| Session store | Rails default **cookie store** (no explicit `session_store`) | `config/` |
| Devise | 4.9.4 — `database_authenticatable, registerable, recoverable, rememberable, validatable, confirmable` | `app/models/user.rb` |
| ActiveRecord Encryption | **Not used** — no `encrypts` declarations | `app/models/` |
| ActiveStorage | `service = :amazon` (S3), `resolve_model_to_route = :rails_storage_proxy` | `config/environments/production.rb` |
| Mailer | SMTP via `smtp-relay.brevo.com`, `raise_delivery_errors = true` | `config/environments/production.rb` |
| Database | `essential-0`, PG 16.13, 6/20 connections, **Fork/Follow Unsupported**, **Rollback Unsupported** | `heroku pg:info` |

### Two scheduling constraints that apply to *every* rotation

**1. Any `heroku config:set` / `config:unset` creates a release and restarts
both dynos — web *and* worker.** Solid Queue now runs on `worker.1`, so a
rotation interrupts in-flight jobs. Solid Queue re-claims interrupted jobs, so
this is recoverable, but the daily supplier block should be avoided.

**Avoid 03:00–07:30 UTC.** Daily jobs run 03:00–05:51 UTC (the heaviest,
`Suppliers::Hlj::TomicaStatusSyncJob`, takes ~11.5 min from 05:40). The Monday
weeklies run 06:00–07:30 UTC. **Preferred window: 14:00–22:00 UTC**, which is
daytime in Mexico and clear of all scheduled jobs.

**2. Rotate one credential per window.** If two are rotated together and the app
breaks, you cannot tell which one did it. Verify each before starting the next.

---

## Recommended order

Ordered **least to most blast radius**, so that confidence is built on the cheap
rotations before the dangerous one:

| # | Credential | Blast radius | Reversible? |
| --- | --- | --- | --- |
| 1 | OpenAI | Two admin features (see §1) | Yes, while old key lives |
| 2 | AWS | All image serving | Yes, if old key retained |
| 3 | Brevo SMTP | Outbound email | Yes, if old key retained |
| 4 | PostgreSQL | Total outage if wrong | **Limited — see §4** |
| 5 | `SECRET_KEY_BASE` | All sessions + Devise tokens | Yes, but user-visible |

---

## 1. OpenAI API credential

**Config key:** `OPENAI_API_KEY`

**Risk.** Grants full API access to the account's OpenAI quota, billed to the
owner. An abused key is a direct financial loss and a rate-limit denial of
service against the features below. This is the highest-likelihood target of
the five — leaked LLM keys are actively harvested and abused — which is why it is
rotated first despite the smallest functional blast radius.

**Client configuration.** `config/initializers/openai.rb` calls
`OpenAI.configure` once at boot with `request_timeout = 60`. Both consumers
construct `OpenAI::Client.new` with no arguments, so they inherit that global
configuration — which means **a key change only takes effect after a dyno
restart**. The Heroku config update forces that restart, so no extra action is
needed.

### Credential precedence — read this before rotating

`config/initializers/openai.rb` resolves the key in this exact order:

```
ENV["OPENAI_API_KEY"]                              (wins if present)
  → Rails.application.credentials.dig(:openai, :api_key)   (only if ENV is blank)
    → nil                                          (app still boots; OpenAI unconfigured)
```

> 🚫 **DO NOT rotate by unsetting `OPENAI_API_KEY`.** The replacement credential
> must be **SET**. Unsetting the variable does not disable OpenAI — it silently
> falls through to the encrypted-credentials entry, which may hold the **old,
> compromised** key. There is no visible symptom: the app boots normally and
> requests keep succeeding against the credential you believed you had retired.

`config/credentials.yml.enc` is tracked in this repository, so the fallback
entry is a real possibility and must be checked rather than assumed absent.

**Pre-flight check — presence only, never the value:**

```bash
bin/rails runner 'puts Rails.application.credentials.dig(:openai, :api_key).present?'
```

This prints exactly `true` or `false` and discloses nothing else. Never use
`credentials:show`, `credentials:edit`, or anything else that renders the
decrypted file into a terminal.

| Result | Meaning | Action |
| --- | --- | --- |
| `false` | No encrypted-credentials OpenAI fallback exists. | Rotating `OPENAI_API_KEY` is sufficient. |
| `true` | An OpenAI credential **also** lives in Rails encrypted credentials and is reachable whenever the ENV var is blank. | It must be **removed or rotated too**, or the compromised key stays reachable. Rotation is not complete until this is resolved. |

---

### Where the credential is consumed — two paths

#### Path A — Product enrichment (asynchronous, `worker.1`)

| Layer | Component |
| --- | --- |
| Entry | `Admin::ProductEnrichmentController#generate` / `#regenerate` |
| Job | `Products::Enrichment::GenerateDraftJob` (`queue_as :enrichment`) |
| Service | `Products::Enrichment::GenerateDraftService` |

Runs on **`worker.1`**. `config/queue.yml` declares `queues: "*"`, so the
dedicated Solid Queue worker serves the `:enrichment` queue.

**Failure behaviour is safe and non-destructive:**

- The job retries — `RateLimitError` ×5 and `GenerationError` ×3, both with
  `wait: :polynomially_longer`; `discard_on ActiveRecord::RecordNotFound`.
- It is idempotent: `perform` returns early if the draft is already
  `draft_generated?` or `published?`.
- On failure the draft reaches a clean terminal state — `status: :failed` with an
  `error_message`. Nothing is left half-written.
- **A failed draft never auto-publishes.** Drafts are staging records;
  product copy changes only through the separate, explicit
  `Products::Enrichment::PublishDraftService`.
- **Business product data therefore remains unchanged until an explicit
  publish.** A bad credential cannot corrupt the catalog.

#### Path B — Purchase-order reception OCR (**synchronous, `web.1`**)

| Layer | Component |
| --- | --- |
| Entry | `Admin::PurchaseOrdersController#build_reception_parser` |
| Service | `PurchaseOrders::ReceptionDocumentParserService` |

Runs **synchronously inside the web request** on **`web.1`** — no job, no retry,
no backoff. Model comes from `ENV["PO_RECEPTION_OCR_MODEL"]` (default `gpt-4o`);
that variable is **not** a secret.

**Failure behaviour:**

- All errors are wrapped as `ReceptionDocumentParserService::ParseError`.
- The controller rescues it, sets a Spanish `flash.now[:alert]`, and renders the
  reception screen with **HTTP 422** (`:unprocessable_entity`).
- **No 500.** The admin sees a readable message, not an error page.
- **Fallback:** CSV uploads route to `PurchaseOrders::ReceptionCsvParserService`,
  which does not call OpenAI at all. PO reception by CSV keeps working even with
  a completely invalid key.

#### Scope of impact

Both paths are **admin-only**. No public or customer-facing surface calls
OpenAI — the storefront, catalog, product pages and checkout are unaffected by an
invalid key.

**No recurring job uses OpenAI.** None of the nine entries in
`config/recurring.yml` touches it, so there is **no automatic OpenAI traffic**: a
broken key produces no background errors and raises no alarm on its own. It stays
silent until an admin acts. **Post-rotation verification must therefore be a
deliberate manual action** — waiting to "see if anything breaks" will not work.

---

### ⚠️ Masked-key safety in error messages

OpenAI authentication failures (401/403) return a message that **may embed a
masked fragment of the submitted key**, in the form
`Incorrect API key provided: sk-…XXXX`.

That string is persisted into `ProductDescriptionDraft#error_message` and also
appears in `worker.1` logs. It is credential material, not neutral diagnostics.

**During rotation diagnosis an agent must NOT:**

- `SELECT` `product_description_drafts.error_message` verbatim
- paste authentication exception text into an AI-visible terminal, report or chat
- print full OpenAI exception bodies

**Allowed instead:**

- read the draft `status` only (`queued` / `generating` / `draft_generated` / `failed`)
- report the error *category* ("OpenAI authentication failure"), not its text
- have the **human** read the detailed message in the admin UI if the specific
  text is genuinely needed

A read that filters columns is fine — for example
`SELECT status, count(*) FROM product_description_drafts GROUP BY status;` —
provided `error_message` is never selected.

---

### Rotation sequence

1. **Run the credentials-fallback presence check** (above). Record `true`/`false`.
2. **If the fallback exists (`true`), plan its remediation too** — the rotation is
   not complete while a compromised key remains reachable through Rails
   credentials.
3. **Create the replacement credential** in the OpenAI console.
4. **Keep the old credential active** for now. OpenAI supports concurrent keys,
   so create-new-before-revoke-old applies cleanly; the old key is the only
   rollback path.
5. **SET `OPENAI_API_KEY`** to the new value through the **Heroku Dashboard**
   (Settings → Config Vars). Not an inline `config:set` — that puts the value in
   shell history and the process argument list. **Never unset** (see precedence).
6. **Allow the restart.** The config change creates a release and restarts both
   `web.1` and `worker.1`.
7. **Verify infrastructure** (below).
8. **Perform one legitimate enrichment action** (below).
9. **Confirm success** before touching the old credential.
10. **Revoke the old credential** in the OpenAI console.
11. **Confirm no compromised fallback remains reachable** — re-run the step-1
    check and confirm the credentials entry has been removed or rotated.

No credential value belongs in any step above.

### Verification

**Infrastructure:**

```bash
heroku ps -a evening-anchorage-70843              # web.1 up, worker.1 up
heroku releases -a evening-anchorage-70843 -n 3   # new release; key NAME only
for p in /up / /catalog; do
  curl -s -o /dev/null -w "$p %{http_code}\n" -L "https://pasatiempos.com.mx$p"
done                                              # expect 200 200 200
heroku logs -a evening-anchorage-70843 -n 200 | grep -E "R1[0-9]|State changed"
```

Confirm Solid Queue re-registered — exactly one hostname, four processes:

```sql
SELECT hostname, string_agg(kind, ',' ORDER BY kind), max(last_heartbeat_at)
FROM solid_queue_processes GROUP BY hostname;
```

**Functional — Path A is the credential proof.**

Use `POST /admin/product_enrichment/:id/generate` from the admin UI. Both
`generate` and `regenerate` create a new `ProductDescriptionDraft`; there is no
in-place re-run action. So **pick a product that genuinely needs enrichment**
rather than manufacturing throwaway data — the verification then doubles as real
work and leaves nothing to clean up.

Success evidence:

- the draft advances `queued → generating → draft_generated`
  (`GET /admin/product_enrichment/:id/status` returns `{status, done}`; the admin
  UI already polls it)
- `worker.1` logs show `Performed Products::Enrichment::GenerateDraftJob`
- the draft has populated `draft_content`, `ai_model`, `tokens_input/output`
- the `solid_queue_failed_executions` count **does not increase**

Failure evidence: the draft flips to `failed` on the first attempt, then retries
three times with polynomial backoff before landing in
`solid_queue_failed_executions` — so a definitive verdict takes roughly two
minutes. Diagnose by *status*, per the masked-key rule above.

**Path B is optional.** Path A already proves the credential works. If you want
coverage of the synchronous path as well, upload one PDF or image on the PO
reception screen and confirm it parses; a bad key yields a 422 with a Spanish
flash, never a 500.

### Rollback

Rollback is possible **only while the old OpenAI key is still active** — which is
precisely why revocation is step 10 and not step 5.

1. In the **Heroku Dashboard**, set `OPENAI_API_KEY` back to the previous value.
2. Both dynos restart (~20–30 s).
3. Confirm `heroku ps` shows `web.1` and `worker.1` up and `/up` returns 200.
4. Confirm Solid Queue re-registered and the queue drains.
5. Re-run the Path A enrichment check and confirm the draft reaches
   `draft_generated`.
6. Investigate the replacement credential before retrying — common causes are
   wrong project scope, insufficient permissions, or a credentials-fallback
   shadow (step 1).

Never paste either the old or the new key into a terminal, an AI assistant
(Claude, ChatGPT or otherwise), a PR, an issue, a commit, or a log.

**Expected side effects.** Dyno restart: **yes** (both `web.1` and `worker.1`).
Sessions: unaffected. Jobs: brief interruption; anything queued during the
restart is re-claimed by Solid Queue. Email/storage: unaffected. Customer-facing
impact: none beyond the ~20–30 s restart.

---

## 2. AWS access credentials

**Config keys:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
(`AWS_REGION` and `AWS_BUCKET` are **not secrets** and do not change.)

**Services used.** S3 only, via ActiveStorage. `config/storage.yml` defines the
`amazon:` service from those four ENV vars; `config/environments/production.rb`
sets `config.active_storage.service = :amazon`.

**Risk.** Grants whatever the IAM principal allows on the `AWS_BUCKET` bucket —
at minimum read/write/delete of every product image and uploaded asset, and
potentially more if the key is over-scoped. Impact: data destruction, content
tampering, and storage-cost abuse.

> Take the opportunity to confirm the IAM policy is scoped to this one bucket.
> If the exposed key was broader than S3, treat the wider surface as compromised
> too and widen this step accordingly.

**Create / rotate.** IAM supports **two concurrent access keys per user**, which
makes create-new-before-revoke-old the natural path:

1. Create a second access key for the same IAM user.
2. Update Heroku.
3. Verify.
4. Deactivate — not delete — the old key.
5. Delete it after a soak period.

**Heroku update.** Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` together
in one Dashboard save, so there is exactly one restart and never a mismatched
pair.

**Verification.** Because `resolve_model_to_route = :rails_storage_proxy`, images
are streamed **through the app** from S3 — so a broken key breaks image serving
site-wide and is immediately visible:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://pasatiempos.com.mx/catalog
# then load a product page with an image and confirm the
# /rails/active_storage/representations/proxy/... request returns 200
```

Read verification is sufficient for this planning step. A write check (uploading
an image) mutates production data and should be done by a human on a disposable
record, if at all.

**Revoke old.** Deactivate after image serving is confirmed. Keep it deactivated
but undeleted for a short soak, since reactivating is instant rollback.

**Rollback.** Reactivate the old key and restore the two config vars.

**Expected side effects.** Dyno restart: **yes**. Sessions: unaffected. Jobs:
`ActiveStorage::AnalyzeJob` may fail during a bad window; those are retried.
**Image outage risk if wrong — this is the most user-visible of the first three.**

---

## 3. Brevo SMTP credential

**Config key:** `BREVO_SMTP_PASSWORD`

**Where it is consumed.** `config/environments/production.rb` sets
`ActionMailer::Base.smtp_settings` with `address: 'smtp-relay.brevo.com'` and
`password: ENV.fetch('BREVO_SMTP_PASSWORD', nil)`.

**Risk.** Allows sending mail **as this domain**. The realistic abuse is phishing
and spam from a trusted sender, which additionally damages domain reputation and
can get the sending domain blocklisted — harm that outlives the rotation.

> 📌 The SMTP **login** (`user_name`) is currently hardcoded in
> `config/environments/production.rb` rather than read from ENV. It is an
> identifier, not a password, so this is not itself the incident — but it is
> poor hygiene and is called out as a follow-up in the PR.

**Create / rotate.** Generate a new SMTP key in the Brevo dashboard. Brevo allows
multiple SMTP keys, so create-new-before-revoke-old applies.

**Heroku update.** Set `BREVO_SMTP_PASSWORD`.

**Verification.** `raise_delivery_errors = true` and `perform_deliveries = true`
are set in production, so a bad credential **raises** rather than failing
silently — good for detection, bad for users if unverified.

Trigger exactly one genuine delivery — a password reset to an address the
operator controls — and confirm no `Net::SMTPAuthenticationError` appears:

```bash
heroku logs -a evening-anchorage-70843 -n 200 | grep -i "smtp\|mailer\|Net::SMTP"
```

Cross-check the Brevo dashboard's transactional log for the send.

**Revoke old.** After a confirmed delivery. Delete the old SMTP key in Brevo.

**Rollback.** Restore the previous `BREVO_SMTP_PASSWORD` while the old key still
exists.

**Expected side effects.** Dyno restart: **yes**. Sessions: unaffected. Jobs:
any mail sent from a job raises on failure. **Email outage risk:** confirmations
and password resets stop working if wrong — and because `:confirmable` is
enabled, a broken mailer blocks new-user onboarding entirely.

---

## 4. PostgreSQL / `DATABASE_URL`

**Config key:** `DATABASE_URL` (Heroku-managed — **never edit it by hand**)

**Add-on:** `postgresql-lively-70068`, plan `essential-0`, PG 16.13.

**Risk.** Full read/write access to all business data — customers, orders,
inventory, and the Devise password digests. This is the most sensitive data
exposure of the five. Note that Heroku Postgres is reachable from the public
internet, so a leaked URL is directly exploitable without any other foothold.

**Use the Heroku-managed mechanism. Do not hand-edit `DATABASE_URL`.**

```bash
# Human-authorized only. Rotates the default credential and updates
# DATABASE_URL automatically. Values are NOT printed by this command.
heroku pg:credentials:rotate postgresql-lively-70068 -a evening-anchorage-70843
```

> ⚠️ **This plan cannot do create-new-before-revoke-old.** Multiple named
> credentials are a Standard-tier-and-above feature; `essential-0` has only the
> default credential. Rotation is therefore **atomic and immediate** — the old
> credential dies the moment the new one is issued. There is no overlap window
> and no gradual migration.

Heroku rotates the credential, updates `DATABASE_URL`, and restarts the dynos.
Expect a **brief connection error window** during the swap.

**Web + worker considerations.** Both dynos hold connections (currently 6 of 20).
Both are restarted by the rotation. Solid Queue's supervisor, dispatcher, worker
and scheduler all reconnect on boot; jobs interrupted mid-flight are re-claimed
after the process registration goes stale. Do not rotate during the 03:00–07:30
UTC job block — an interrupted 11-minute `TomicaStatusSyncJob` is the worst case.

**Verification.**

```bash
heroku pg:info -a evening-anchorage-70843     # Status: Available, connections recovering
heroku ps -a evening-anchorage-70843          # web.1 and worker.1 up
curl -s -o /dev/null -w "%{http_code}\n" https://pasatiempos.com.mx/up
```

Then confirm Solid Queue re-registered — exactly one hostname with four
processes and a fresh heartbeat:

```sql
SELECT hostname, string_agg(kind, ',' ORDER BY kind), max(last_heartbeat_at)
FROM solid_queue_processes GROUP BY hostname;
```

**Revoke old.** Not applicable — rotation *is* revocation on this plan.

**Rollback.** ⚠️ **Effectively none.** The old credential is gone, and
`heroku pg:info` reports **Rollback: Unsupported** and **Fork/Follow:
Unsupported** on `essential-0` — so there is no follower to fail over to and no
point-in-time rollback. If the app cannot connect after rotation, the path
forward is to fix connectivity, not to restore the old credential. Continuous
Protection is On, which covers data loss, not credential recovery.

**Because this step is one-way, it should be scheduled deliberately, with a
human watching, in the low-traffic window — not bundled with anything else.**

**Expected side effects.** Dyno restart: **yes**, forced by Heroku. Sessions:
unaffected (cookie-based, not DB-backed). Jobs: interrupted and re-claimed.
Brief total-unavailability window during the swap.

---

## 5. `SECRET_KEY_BASE` — most delicate

**Config key:** `SECRET_KEY_BASE`

**Risk.** This is the master key from which Rails derives every message
verifier and encryptor. With it, an attacker can **forge session cookies and
authenticate as any user, including an admin**, and mint valid signed
ActiveStorage URLs. It is the single most severe item on this list, and the one
most likely to be under-appreciated because nothing visibly breaks while it is
compromised.

**What it does *not* affect here.** The app declares **no** `encrypts` columns —
ActiveRecord Encryption is unused — so **no data at rest becomes unreadable**.
This substantially de-risks the rotation and is the key finding that makes a
staged approach practical.

### What breaks on a naive swap

| Surface | Mechanism | Effect of a blind rotation |
| --- | --- | --- |
| Session cookies | Default cookie store, encrypted with a key derived from `secret_key_base` | **Every user logged out** |
| "Remember me" | `:rememberable` signed cookie | All remember-me cookies invalid |
| Password reset | Devise `TokenGenerator`, digest stored in `users.reset_password_token` | **In-flight reset links stop working** |
| Email confirmation | Same generator, `users.confirmation_token` | **In-flight confirmation links stop working** — and `ensure_confirmed_user!` signs out unconfirmed users, so affected signups are stuck |
| ActiveStorage signed IDs | `Rails.application.message_verifiers` | Previously-issued proxy URLs 404; newly rendered pages are fine |

Devise's dependency is concrete: `config.secret_key` is commented out in
`config/initializers/devise.rb`, so Devise falls back to `secret_key_base`, and
`Devise::TokenGenerator#key_for` derives its HMAC key as
`key_generator.generate_key("Devise #{column}")`. The stored token is a digest,
so changing the key orphans every outstanding token.

### Rails 8 does support rotation — two distinct mechanisms

Both were verified against the installed gems (actionpack/railties 8.0.1):

**a. Cookie rotation** — `config.action_dispatch.cookies_rotations`, applied in
`ActionDispatch::Cookies` for both the signed and encrypted jars. Cookies signed
with the *old* secret continue to verify, and Rails transparently re-writes them
with the new secret on next use (`force_reserialize` on rotation).

**b. Message verifier rotation** — `Rails.application.message_verifiers.rotate(secret_key_base: "old value")`,
documented in `Rails::Application#message_verifiers`. New messages always use the
current `secret_key_base`; old ones still verify.

⚠️ **These are separate.** Cookie jars build their own verifier from
`request.key_generator`, so `message_verifiers.rotate` alone does **not** keep
sessions alive. A session-preserving rotation needs **both**.

### Staged strategy

**Stage 0 — decide whether to preserve sessions at all.**
Preserving sessions requires temporarily holding the *old* (compromised)
`SECRET_KEY_BASE` in the environment as a second config var so it can be used for
verification-only. That keeps a compromised value live in production for the
overlap period.

Given this app's size, the honest recommendation is **the simple path: accept the
logout.** Rotate in the low-traffic window, let every user re-authenticate, and
never hold the compromised key in production at all. Sessions are the *only*
thing preserved by the complex path, and forcing re-authentication is arguably
desirable after a key compromise — anyone riding a forged session is ejected.

**Stage 1 — simple path (recommended).**

1. Schedule in the low-traffic window (14:00–22:00 UTC), announced if possible.
2. Generate a new value with `rails secret` **locally**; do not print it.
3. Set `SECRET_KEY_BASE` via the Heroku Dashboard.
4. Both dynos restart. Everyone is logged out.
5. Verify (below).
6. Tell users that outstanding password-reset and confirmation emails must be
   re-requested.

**Stage 2 — session-preserving path (only if a logout is unacceptable).**

This requires a **code change**, which is why it is planning-only here and not
implemented in this PR:

```ruby
# config/initializers/secret_key_base_rotation.rb
# TEMPORARY — remove, and unset OLD_SECRET_KEY_BASE, after the overlap window.
if (old = ENV["OLD_SECRET_KEY_BASE"]).present?
  old_generator = ActiveSupport::KeyGenerator.new(old, iterations: 1000)

  Rails.application.config.action_dispatch.cookies_rotations.tap do |cookies|
    cookies.rotate :signed,
      old_generator.generate_key(Rails.application.config.action_dispatch.signed_cookie_salt)
    cookies.rotate :encrypted,
      old_generator.generate_key(
        Rails.application.config.action_dispatch.authenticated_encrypted_cookie_salt,
        ActiveSupport::MessageEncryptor.key_len)
  end

  Rails.application.config.before_initialize do |app|
    app.message_verifiers.rotate(secret_key_base: old)
  end
end
```

Sequence: deploy the initializer while the old key is still current (it is inert
until `OLD_SECRET_KEY_BASE` is set) → set `OLD_SECRET_KEY_BASE` to the old value
and `SECRET_KEY_BASE` to the new one in a single save → soak for one session
lifetime → unset `OLD_SECRET_KEY_BASE` → remove the initializer.

Even this does **not** rescue Devise reset/confirmation tokens; Devise offers no
rotation hook, so those links break either way.

**Verification (both paths).**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://pasatiempos.com.mx/up
curl -s -o /dev/null -w "%{http_code}\n" https://pasatiempos.com.mx/users/sign_in
```

Then, by hand: sign in as a test user; confirm a product image still renders
(exercises `message_verifiers` for ActiveStorage); request a password reset and
confirm the new link works.

**Revoke old.** Discard the old value once the overlap window closes. In the
simple path there is no overlap.

**Rollback.** Restore the previous `SECRET_KEY_BASE`. This logs everyone out a
second time but is otherwise safe — **because no data at rest is encrypted with
it.** That property is what makes this rotation recoverable at all.

**Expected side effects.** Dyno restart: **yes**. Sessions: **all invalidated**
(simple path). Jobs: interrupted and re-claimed. Email: unaffected mechanically,
but outstanding reset/confirmation links are dead.

---

## Post-rotation checklist

- [ ] Each credential rotated in its own window, verified before the next
- [ ] Old credentials revoked after verification, not before
- [ ] `heroku releases -n 20` shows the expected `Set … config vars` entries, key names only
- [ ] `heroku ps` shows `web.1` and `worker.1` up
- [ ] `solid_queue_processes` shows exactly one hostname with four processes
- [ ] `solid_queue_failed_executions` count has not increased
- [ ] No credential value appears in any log, report, commit, or PR
- [ ] OpenAI only: credentials-fallback presence re-checked and confirmed
      remediated, so no compromised key remains reachable (§1)
- [ ] No provider authentication-error text — which may embed a masked key
      fragment — was pasted into a terminal, report or AI session (§1)
- [ ] Follow-up: move the Brevo SMTP `user_name` out of
      `config/environments/production.rb` into an ENV var
- [ ] Follow-up: remove the commented-out generated example secrets from
      `config/initializers/devise.rb` (inert, but should not be committed)
