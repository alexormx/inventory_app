# Production secret safety

How to inspect production **without** dumping credential values into a terminal,
a log, a report, or an AI agent's context.

This document exists because of a real incident: during a diagnostic session an
agent ran `heroku releases:info`, which prints the **entire config var set** for
a release. Several production credential values were thereby written into
AI-visible terminal history. No attacker was involved and nothing was stolen,
but the values must be treated as compromised, because they were disclosed
outside their intended trust boundary.

The remediation is **credential rotation**, not history rewriting. See
[credential_rotation_runbook.md](credential_rotation_runbook.md).

---

## The core rule

> Never run a command whose output includes credential **values**.
> Prefer commands that return **metadata** — names, states, timestamps, counts.

Almost every production question can be answered from metadata. If you think you
need a secret value, you almost certainly need to *use* the credential, not *see*
it.

---

## Prohibited commands

These print secrets, or can, and must never be run by an agent:

| Command | Why it is unsafe |
| --- | --- |
| `heroku releases:info [vNNN]` | Prints the **full config var set** for the release. This caused the incident. |
| `heroku config` | Prints every config var with values. |
| `heroku config --json` | Same, machine-readable. |
| `heroku config:get <KEY>` | Prints that credential's value. |
| `heroku run env` | Dumps the whole dyno environment. |
| `heroku run printenv` | Same. |
| `heroku pg:credentials:url` | Prints database connection credentials. |
| `env`, `printenv`, `set`, `export -p` | Dump the local environment, which may hold credentials. |

Also avoid anything that enumerates the environment indirectly — for example
`heroku run 'ruby -e "puts ENV.inspect"'` or `heroku run rails runner 'puts ENV.to_h'`.
The rule is about the *output*, not the command name.

`heroku config:set` / `heroku config:unset` are **not** in this list, and are
safe for **non-secret** flags, because they do not read a value back. Setting a
*secret* value on the command line is still unsafe — see
[Writing a secret without echoing it](#writing-a-secret-without-echoing-it).

---

## Safe alternatives

| You need | Use instead | Returns |
| --- | --- | --- |
| Current release number / deployed SHA | `heroku releases -a <app> -n 5` | Version, `Deploy <short-sha>` description, author, timestamp — no config values |
| Whether a deploy or config change happened | `heroku releases -a <app> -n 10` | Release list; a config change shows as `Set/Remove <KEY> config vars` — **key names only** |
| Dyno state, uptime, restarts | `heroku ps -a <app>` | Process types, state, uptime |
| Current scale / dyno sizes | `heroku ps:scale -a <app>` | Formation only |
| Database metadata | `heroku pg:info -a <app>` | Size, connections, PG version, plan — no credentials |
| Recent errors | `heroku logs -a <app> -n 200`, optionally `--dyno web.1` | Bounded log output |
| App metadata / add-ons | `heroku info -a <app>` | Region, stack, add-on names, web URL |
| Whether a config key exists | `heroku releases -n 20` and read the `Set …` release descriptions | Key names, never values |
| Log destinations | `heroku drains -a <app>` | ⚠️ Drain URLs may embed tokens — redact to scheme+host before printing |

### Deriving the deployed SHA safely

`heroku releases -n 5` shows `Deploy <short-sha>`. Match it against git:

```bash
heroku releases -a <app> -n 5          # read the short SHA from the description
git rev-parse HEAD                     # compare locally
git ls-remote heroku main              # authoritative deployed ref
```

No release config dump is needed to answer "what is deployed".

---

## Working with credentials without seeing them

### Reading a single key's presence

Do not use `config:get`. If you must confirm a key is set, infer it from
behaviour (the feature works) or from the release list (`Set <KEY> config vars`).

### Writing a secret without echoing it

`heroku config:set KEY=value` places the value in the terminal, in shell history,
and in the agent's context. When a human rotates a credential, they should set it
through the **Heroku Dashboard** (Settings → Config Vars), or from a shell where
the value is read from a file or a prompt rather than typed inline:

```bash
# Human-only. Reads from a local file that is never printed or committed.
heroku config:set OPENAI_API_KEY="$(cat ~/.secrets/openai_new)" -a <app>
```

Even then the value lands in the process argument list. The Dashboard is
preferred for secret values.

### Testing secret-backed functionality

Consume the credential, never echo it. Assert on *behaviour*:

- S3: does an ActiveStorage attachment render / download?
- SMTP: does a real mailer action deliver without raising?
- OpenAI: does an enrichment draft generate?
- Postgres: does a read-only `SELECT 1` succeed?

A check that prints the credential is not a better check.

---

## Never place a credential value in

- terminal output
- a final report or summary
- a commit, a commit message, or a PR description
- an issue or PR comment
- a log you generate deliberately for debugging
- a test fixture or a spec

Refer to credentials by **key name** only: `OPENAI_API_KEY`, `AWS_SECRET_ACCESS_KEY`,
`BREVO_SMTP_PASSWORD`, `DATABASE_URL`, `SECRET_KEY_BASE`.

---

## If a secret is printed anyway

1. **Stop** all secret-related inspection immediately.
2. **Do not repeat, re-read, echo, diff, or "verify" the value.** Re-printing it
   to confirm what leaked doubles the exposure.
3. Do not try to scrub it from shell history, chat history, git history, or
   Heroku release history. Those are not reliable containment, and the attempt
   often re-exposes the value.
4. Report only the **credential category** — "an AWS access key was exposed" —
   never the value or a fragment of it.
5. Recommend rotation and hand off to a human. Rotation is the containment.

---

## Authorization

Production credential rotation, and any `heroku config:set` of a secret value,
**requires explicit human authorization in the current turn**. A prior approval,
a general "you are authorized to operate production" grant, or an inference from
task context never satisfies this. If unsure, it is not authorized: stop and ask.
