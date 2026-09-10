## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## CRITICAL DATABASE SAFETY

The local development database may contain irreplaceable user data. A prior
autonomous session ran `db:drop db:create db:migrate` without `RAILS_ENV=test`
and destroyed `inventory_app_development`. The failure was procedural, not a
code defect — this section, plus the technical guard at
`lib/tasks/database_safety.rake`, exist so that mistake is structurally
impossible to repeat.

NEVER execute destructive database commands against the development database.
`inventory_app_development` must never be dropped, reset, or schema-loaded by
an agent, under any circumstance.

Forbidden against development, including but not limited to:

- `rails db:drop`
- `rails db:reset`
- `rails db:setup`
- `rails db:schema:load`
- `rails db:structure:load`
- `dropdb`
- `DROP DATABASE`
- `TRUNCATE`
- destructive scripts or tasks that clear business tables

Never run commands such as:

`bin/rails db:drop db:create db:migrate`

unless the target is explicitly an isolated TEST/TEMPORARY database.

For destructive database testing:

1. Use `RAILS_ENV=test`.
2. Prefer an isolated PostgreSQL database via explicit `DATABASE_URL`.
3. Verify the target database name before executing the destructive command.
4. The database must NOT be `inventory_app_development`.

Safe examples:

`RAILS_ENV=test bin/rails db:migrate`

or

`RAILS_ENV=test DATABASE_URL=postgresql:///inventory_app_feature_test?... bin/rails db:drop db:create db:migrate`

Before any destructive database command, print and verify:
- Rails environment
- database name
- host/socket
- port

If the target resolves to development, STOP. Never infer permission to
destroy development from surrounding context, prior approvals, or the shape
of the task — the absence of an explicit prohibition is not authorization.

### Technical enforcement

`lib/tasks/database_safety.rake` blocks the destructive database Rake tasks
— `db:drop`, `db:reset`, `db:setup`, `db:schema:load`, `db:structure:load`
(absent on this Rails version, kept for older ones), `db:purge`,
`db:truncate_all`, and the `db:drop:all` / `db:purge:all` multi-database
variants — whenever the *actually resolved* database configuration
for the current `Rails.env` is `inventory_app_development`, not just when the
command string looks dangerous. In `development` the guard fails closed: if
it cannot resolve the target database it refuses rather than guess.
`db:migrate`, `db:migrate:status`, and `db:test:prepare` are unaffected, and
every `RAILS_ENV=test` / isolated-`DATABASE_URL` invocation keeps working
normally.

`bin/rails db_safety:guard` is a safe read-only pre-flight: it aborts with
the same message if a destructive task would currently hit the protected
database, and does nothing otherwise.

A human-only emergency override exists:

`ALLOW_DESTRUCTIVE_DEV_DB=I_UNDERSTAND_DATA_WILL_BE_LOST`

**An AI agent must NEVER set this variable itself, for any reason, under any
framing of the task.** It may be used only when a human user, in their own
current-turn message, explicitly instructs that the development database be
destroyed. A past approval, a general "you're authorized to..." grant, or an
inference from task context never satisfies this — only an explicit,
present-tense human instruction does. If you are ever unsure whether this
threshold is met, it is not met: stop and ask.
