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
| 1 | OpenAI | One admin feature | Yes, trivially |
| 2 | AWS | All image serving | Yes, if old key retained |
| 3 | Brevo SMTP | Outbound email | Yes, if old key retained |
| 4 | PostgreSQL | Total outage if wrong | **Limited — see §4** |
| 5 | `SECRET_KEY_BASE` | All sessions + Devise tokens | Yes, but user-visible |

---

## 1. OpenAI API credential

**Config key:** `OPENAI_API_KEY`

**Risk.** Grants full API access to the account's OpenAI quota, billed to the
owner. An abused key is a direct financial loss and a rate-limit denial of
service against the enrichment feature. This is the highest-likelihood target of
the five — leaked LLM keys are actively harvested and abused — which is why it is
rotated first despite the smallest functional blast radius.

**Where it is consumed.** `config/initializers/openai.rb` reads
`ENV.fetch("OPENAI_API_KEY", nil)` and falls back to
`Rails.application.credentials.dig(:openai, :api_key)`. Used by the product
enrichment path (`Admin::ProductEnrichmentController`,
`Products::Enrichment::GenerateDraftJob`).

> ⚠️ **Check the fallback before rotating.** If a value is also baked into Rails
> encrypted credentials, clearing the ENV var silently falls back to the old,
> compromised key. Confirm which source is live, and rotate the credentials
> entry too if one exists.

**Create / rotate.** Create a **new** key in the OpenAI dashboard first. OpenAI
supports multiple concurrent keys, so create-new-before-revoke-old applies
cleanly.

**Heroku update.** Set `OPENAI_API_KEY` to the new value — via the Heroku
Dashboard (Settings → Config Vars), not an inline shell command.

**Verification.** Generate one enrichment draft from the admin UI and confirm it
completes. Because generation runs as a job, confirm on the worker:

```bash
heroku logs -a evening-anchorage-70843 --dyno worker.1 -n 100
# expect: Performed Products::Enrichment::GenerateDraftJob ... (no 401)
```

A 401 from OpenAI surfaces as a job failure; check `solid_queue_failed_executions`
count is unchanged.

**Revoke old.** Only after a successful draft. Delete the old key in the OpenAI
dashboard.

**Rollback.** Re-set `OPENAI_API_KEY` to the previous value — possible only while
the old key still exists, which is the reason revocation is last.

**Expected side effects.** Dyno restart: **yes** (both). Sessions: unaffected.
Jobs: brief interruption; enrichment drafts queued during the restart are
re-claimed. Email/storage: unaffected.

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
- [ ] Follow-up: move the Brevo SMTP `user_name` out of
      `config/environments/production.rb` into an ENV var
- [ ] Follow-up: remove the commented-out generated example secrets from
      `config/initializers/devise.rb` (inert, but should not be committed)
