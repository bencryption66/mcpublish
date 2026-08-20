# Core Hosting Engine — Design

Date: 2026-08-19
Status: Approved
Sub-project: 1 of 4 (see "Project decomposition" below)

## Context

mcpublish.ai is a platform where companies and individuals register, connect
their AI agent via MCP, and have that agent publish HTML artifacts / pages
that can later be shared with team members or the public.

The full product bundles several independent subsystems: accounts/auth, the
artifact hosting engine itself, sharing/permissions, and a dashboard UI.
Building all of that as one spec would be too broad, so it's decomposed into
sub-projects, each with its own spec → plan → build cycle:

1. **Core hosting engine** (this spec) — an MCP server that accepts an
   artifact from an agent, stores it, and serves it at a URL. The novel,
   technically risky part; everything else is standard SaaS scaffolding once
   this works.
2. **Accounts & auth** — registration, orgs/teams, real API key issuance tied
   to an account (replaces the manual key issuance used in this sub-project).
3. **Sharing & permissions** — private/team/public visibility, link sharing,
   revocation.
4. **Dashboard/web UI** — browsing hosted artifacts, managing team, usage.

This spec covers sub-project 1 only.

## Goals

- An agent, connected over MCP, can publish a single self-contained HTML
  artifact and get back a working public URL.
- The agent can update, list, and delete artifacts it previously published.
- Requests are attributed to a manually-issued API key (no signup flow yet —
  that's sub-project 2).
- Artifact content is served from an origin isolated from the main app, so
  agent-generated HTML/JS cannot access the main app's session or cookies.
- Storage is modeled so multi-file sites (index.html + assets) can be added
  later without a rewrite, even though only single-file HTML is supported now.

## Non-goals (deferred to later sub-projects)

- User registration, login, org/team membership.
- Visibility controls (everything reachable by its slug is effectively
  public-by-obscurity in this sub-project; real private/team/public controls
  land in sub-project 3).
- Any dashboard or web UI for browsing artifacts.
- Multi-file site support (design allows for it, but it is not implemented
  here).

## Architecture

- **Single Rails 8 app**, deployed on AWS (ECS + RDS Postgres + S3 for
  artifact storage).
- **`mcpublish.ai`** — hosts the MCP endpoint (Streamable HTTP transport,
  since this is a remote hosted server rather than a local stdio process) at
  `POST /mcp`. This origin will later also host the dashboard and accounts
  (sub-projects 2 and 4).
- **`content.mcpublish.ai`** — same Rails codebase, routed via a host
  constraint to a dedicated controller that serves only artifact HTML. Rack
  middleware is global — it cannot be scoped to a single route — so the real
  guarantee is at the controller layer: this controller inherits
  `ActionController::API` directly, never `ApplicationController`, so it
  never includes `ActionController::Cookies` and structurally cannot read or
  set cookies regardless of what middleware the main app later loads (e.g.
  sessions in sub-project 2). Combined with a host-scoped session cookie (see
  the caveat below), the browser has no session cookie to send here even if
  it wanted to.
- **Postgres** holds metadata (API keys, artifact records). **S3** holds the
  actual HTML bytes, keyed by artifact id. Keeping content out of the DB
  keeps it small and lets multi-file sites be added later as just more S3
  objects per artifact, with no schema rewrite.

### Cookie scoping caveat

The main app's session cookie must be scoped to the exact host `mcpublish.ai`
(no leading-dot domain like `.mcpublish.ai`). A dotted domain cookie would be
sent to `content.mcpublish.ai` as well, defeating the origin isolation this
design relies on. This must be set explicitly in Rails' session store config
when accounts/sessions are introduced in sub-project 2 — there's no session
store in this sub-project yet, but the constraint is recorded here since it's
foundational to why the subdomain split is safe.

## Data model

**ApiKey**
| column | type | notes |
|---|---|---|
| id | uuid/bigint | |
| token_digest | string | hashed; raw token is shown once at issuance and never stored |
| label | string | who the key is for; set manually by the operator |
| created_at | datetime | |
| revoked_at | datetime, nullable | manual revocation |

**Artifact**
| column | type | notes |
|---|---|---|
| id | uuid/bigint | |
| slug | string | unique, random (~8-char base62), always server-generated |
| api_key_id | fk → ApiKey | owner |
| storage_key | string | S3 object path |
| byte_size | integer | |
| created_at | datetime | |
| updated_at | datetime | bumped on `update_artifact` |

No `content_type`/multi-file columns yet — deliberately deferred until
multi-file sites are actually built, to avoid speculative schema.

## MCP tool interface

All four tools are scoped to the calling API key (resolved from the request's
auth, not passed as a tool argument).

- **`publish_artifact(html: string)`** → `{ slug, url }`
  Creates a new artifact. Rejects if `html` exceeds the size limit. Slug is
  always server-generated (no agent-suggested slugs, to avoid collision
  handling and slug-squatting between users). Returns
  `https://content.mcpublish.ai/p/<slug>`.

- **`update_artifact(slug: string, html: string)`** → `{ slug, url }`
  Overwrites an existing artifact's content in place (same slug/URL). Errors
  if the slug doesn't exist *or* isn't owned by the calling key — both cases
  return the identical generic error, so a valid key can't be used to probe
  for the existence of other users' slugs.

- **`list_artifacts()`** → `[{ slug, url, byte_size, created_at, updated_at }]`
  All artifacts owned by the calling key.

- **`delete_artifact(slug: string)`** → `{ success: true }`
  Deletes the artifact record and its S3 object. Same ownership-check/error
  behavior as `update_artifact`.

## Content serving

`GET content.mcpublish.ai/p/:slug`:

- Looks up the artifact by slug, streams the HTML from S3.
- Response headers: `Content-Type: text/html`, no `Set-Cookie`. Session/cookie
  middleware is present globally in the Rack stack (it has to be, to support
  the web UI added in sub-project 4), so it is no longer accurate to say no
  session store is active on this subdomain's routes. What actually backs
  the isolation claim now: `ApplicationController` and `ContentController`
  both override `session` to raise immediately if it is ever called, making
  touching it a hard failure rather than a silent possibility.
- No long-lived caching — content can change via `update_artifact`, so
  responses are served fresh each time (no `Cache-Control: immutable` or
  long-TTL caching).
- Unknown or deleted slug → plain 404.

## Abuse limits

- **Size cap**: 5MB per `publish_artifact`/`update_artifact` call.
- **Rate limit**: ~30 publish/update calls per minute per API key, via
  `rack-attack`. Prevents a runaway agent loop from generating unbounded
  storage/S3 cost even from a trusted, manually-issued key.

These are intentionally basic since keys are manually issued to trusted early
users; tighter abuse controls are expected before public registration opens
in sub-project 2.

## Error handling

- Missing/invalid/revoked API key → MCP tool error, rejected before any S3
  interaction.
- Oversized `html` → rejected with a clear size-limit error before upload is
  attempted.
- Not-found or not-owned slug on `update_artifact`/`delete_artifact` →
  identical generic error in both cases (see above — avoids slug
  enumeration).
- S3 failures → surfaced to the agent as a retryable error, not swallowed.

## Testing approach

- Request specs against the MCP endpoint covering: valid key success path
  for all four tools, invalid/revoked key rejection, size-limit rejection,
  not-found/not-owned error parity for update/delete, rate-limit rejection.
- S3 interaction stubbed/faked in tests (e.g. via a Minio container or S3
  stub) rather than hitting real S3.
- Content-serving specs verifying: correct HTML returned for a valid slug,
  404 for unknown/deleted slug, no `Set-Cookie` header present, response
  works when requested against the `content.mcpublish.ai` host specifically
  (not just the default test host), confirming the subdomain routing
  constraint actually applies.
