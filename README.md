# mcpublish — core hosting engine

A Rails 8 API app exposing an MCP (Model Context Protocol) server. An
authenticated agent publishes, updates, lists, and deletes single-file HTML
"artifacts"; each is served back at a public URL on an origin-isolated
content subdomain.

This is sub-project 1 (of 4) of the mcpublish product. See
`docs/superpowers/specs/2026-08-19-core-hosting-engine-design.md` for the
design rationale and `docs/superpowers/plans/2026-08-19-core-hosting-engine.md`
for the implementation plan and history.

## Prerequisites

* Ruby 3.3.8 (see `.ruby-version`)
* A local PostgreSQL server, running and reachable with the credentials in
  `config/database.yml` (or override via `DATABASE_URL`)

No AWS credentials are needed for local development or tests — S3 calls are
stubbed in the test environment (`config/initializers/aws.rb`), and nothing
in this sub-project has been deployed yet (see "Deployment" below).

## Setup

```bash
bundle install
bin/rails db:create
bin/rails db:migrate
```

## Running the test suite

```bash
bundle exec rspec
```

Lint and static analysis (also run in CI):

```bash
bin/rubocop
bin/brakeman --no-pager
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CONTENT_HOST` | `content.mcpublish.ai` | Host that serves published artifacts (`GET /p/:slug`). Also used to build the public URL returned by `publish_artifact`/`update_artifact`. Routes are constrained so the main app's routes (`/mcp`, `up`) are only reachable when the request host does **not** match this value — see `config/routes.rb`. |
| `ARTIFACTS_S3_BUCKET` | `mcpublish-artifacts-development` | S3 bucket artifact HTML is stored in. |
| `AWS_REGION` | `us-east-1` | Region for the S3 client, outside the test environment. |
| `DATABASE_URL` | (from `config/database.yml`) | Overrides the Postgres connection. |

## Issuing an API key

There is no self-service registration yet (that's sub-project 2). Keys are
issued manually:

```bash
bin/rails "api_keys:issue[some-label]"
```

This prints a raw token once — it is not stored anywhere retrievable, so
save it immediately. The label is just an operator-facing note (who the key
is for); it isn't used for anything else.

Agents authenticate MCP requests with `Authorization: Bearer <token>`
against `POST /mcp`.

## Deployment

Not part of this sub-project. The design targets AWS (ECS + RDS Postgres +
S3), but no infrastructure-as-code, Dockerfile tuning beyond Rails'
defaults, or DNS/TLS setup for the content host has been done yet — that's
a separate infra task once this app is verified end-to-end.
