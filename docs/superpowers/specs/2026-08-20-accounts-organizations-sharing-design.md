# Accounts, Organizations & Sharing — Design

Date: 2026-08-20
Status: Approved
Sub-project: replaces the originally-planned sub-projects 2 ("Accounts &
auth") and 3 ("Sharing & permissions") from the core hosting engine spec,
combined into one design because they turned out to be too tightly coupled
to design independently — the origin-isolation approach for gated content
depends entirely on the exact visibility model, which depends on the
user/org data model.

## Context

Sub-project 1 (core hosting engine, already shipped) treats every artifact
as public-by-obscurity: anyone with the slug can view it, agents authenticate
with a manually-issued API key, and there are no user accounts. This design
adds real accounts, organizations, and per-artifact visibility control:
**private** (owner only), **organisation** (members of one of the owner's
orgs), **shared** (specific people, by email, invited or not), and
**public** (unauthenticated, link-only — sub-project 1's current behavior).

## Goals

- Users can sign up, log in, and generate their own API keys (replacing
  manual issuance).
- Users can create organizations and invite/remove members.
- An agent can set an artifact's visibility at publish time and change it
  later, without needing a dashboard.
- A signed-in human can view a private/organisation/shared artifact they
  have permission to see, in a browser.
- The content-serving host (`content.mcpublish.ai`) still never gains a
  session cookie — the confused-deputy risk that would create (one
  artifact's JS riding a viewer's ambient session to read a different,
  private artifact same-origin) is closed architecturally, not by policy.
- Not-found and not-permitted look identical everywhere probing could
  otherwise leak information (matches sub-project 1's existing
  not-found/not-owned parity principle).

## Non-goals (deferred)

- Password reset, email confirmation, 2FA — fast-follow once basic auth is
  proven out.
- Any artifact-browsing, artifact-management, or org-settings-beyond-basics
  UI (renaming an org, changing roles beyond admin/member, org deletion) —
  that's sub-project 4's dashboard. The UI built here is the minimum needed
  to make accounts, API keys, and organizations usable at all: signup,
  login/logout, API key generate/revoke, and org create/list/invite/remove
  member. Nothing beyond that.
- Devise or any other auth gem — hand-rolled (`has_secure_password` +
  a plain session controller), since the deferred password-reset scope was
  the main thing a gem would have saved, and the session cookie's
  exact-host scoping requirement is easier to keep correct in code we
  wrote ourselves.
- Fine-grained org roles beyond admin/member.
- Revoking an already-issued signed content-access token before it expires
  (natural expiry is the only revocation mechanism at launch).

## Architecture

### Data model

- **User**: `email` (unique), `password_digest` (bcrypt via
  `has_secure_password`).
- **Organization**: `name`, `slug` (unique — used in the MCP tools'
  `organization` param).
- **OrganizationMembership**: joins `User`↔`Organization`, `role`
  (`admin`/`member`). Unique on `[user_id, organization_id]`. The creator of
  an org becomes its first `admin`; admins can invite/remove members,
  members can create/view org-visibility artifacts but not manage
  membership.
- **ApiKey**: gains `belongs_to :user` (previously ownerless/manual). A user
  can hold several, each independently labeled and revocable.
- **Artifact**: ownership moves from `belongs_to :api_key` to
  **`belongs_to :user`** — the key that published it is how the request
  authenticated, not who owns it; a user with multiple keys should be able
  to manage an artifact regardless of which key published it. Gains
  `visibility` (enum: `private`/`organisation`/`shared`/`public`, default
  `private`) and a nullable `organization_id` (set only when
  `visibility == "organisation"`).
- **ArtifactShare**: `artifact_id`, `email`, nullable `user_id`. One row per
  person an artifact is shared with. `user_id` starts nil for an invited
  email with no account; signup looks up `ArtifactShare` rows matching the
  new user's email and claims them (sets `user_id`) automatically.
- **OrganizationInvite**: `organization_id`, `email`. Created when an org
  admin invites someone who may or may not have an account yet; signup
  looks up matching invites by email and turns each into a real
  `OrganizationMembership` (role `member`) automatically, then deletes the
  invite.

### Authentication

- Standard Rails session-based login: signup, login, logout, using
  `has_secure_password`.
- The session cookie is scoped to the **exact host** `mcpublish.ai` (no
  leading-dot domain) — this fulfills the cookie-scoping caveat already
  recorded in sub-project 1's design doc, and is what keeps the cookie from
  ever being sent to `content.mcpublish.ai`.
- This requires re-enabling session/cookie middleware for the main app's
  routes (the app is currently pure `--api` mode with none loaded). The
  content-serving routes must not gain this middleware — same isolation
  principle as sub-project 1, just now something to actively preserve
  rather than get for free from `--api` mode.

### Minimal UI

Kept deliberately small — just enough to make accounts, keys, and orgs
usable without a dashboard:

- Signup, login, logout pages.
- "Your API keys" page: generate (raw token shown once, same UX as
  sub-project 1's rake task), label, revoke.
- "Your organizations" page: create an org (creator becomes admin), list
  orgs you belong to, invite a member by email, remove a member (admin
  only). Inviting by email works whether or not that person has an account
  yet: an `OrganizationInvite` record (`organization_id`, `email`) is
  created immediately, and claimed the same way `ArtifactShare` is — signup
  checks for matching invites by email and turns each into a real
  `OrganizationMembership` automatically.
- No artifact-browsing or artifact-visibility-management UI — that stays
  entirely agent-mediated via the MCP tools until sub-project 4.

The old `rails api_keys:issue[label]` rake task is removed; self-service
replaces it entirely.

### MCP tool interface changes

- `publish_artifact` gains three optional params:
  - `visibility` (`private`/`organisation`/`shared`/`public`, default
    `private`)
  - `organization` (org slug — required when `visibility == "organisation"`;
    must be one the calling user belongs to, generic "not found" error
    otherwise, matching the no-existence-leak principle)
  - `shared_with` (array of emails — used when `visibility == "shared"`;
    invalid email format is rejected)
- `update_artifact` accepts the same three params, **independent of
  `html`** — visibility can change without resending content. When
  provided, each param **replaces** the current value (`shared_with:
  ["a@x.com"]` fully replaces the share list — that's how a share is
  revoked: resend the list without that person). When omitted, the
  existing value is unchanged. Switching away from `organisation` clears
  `organization_id`; switching away from `shared` clears the artifact's
  `ArtifactShare` rows.
- `list_artifacts` includes `visibility`, `organization`, and
  `shared_with` in each returned artifact so the agent can report current
  sharing state back to the user.

### Gated content-serving

The core architectural resolution: **`content.mcpublish.ai` never gains a
session cookie.** Giving it one (even `HttpOnly`) would let a malicious
artifact's JavaScript ride the viewer's ambient, browser-auto-attached
cookie via a same-origin `fetch()` to a *different*, private artifact —
a confused-deputy attack against private content, strictly worse than the
same-origin risk sub-project 1 already isolated against for public content.

**Public artifacts**: unchanged. `GET content.mcpublish.ai/p/:slug` serves
directly, no auth.

**Gated artifacts** (`private`/`organisation`/`shared`):

1. `GET content.mcpublish.ai/p/:slug` with no valid `token` param → the
   content host has no way to make a permission decision, so it redirects
   to `mcpublish.ai/artifacts/:slug/view`.
2. That main-app endpoint has a real session. If the visitor isn't signed
   in, redirect to login with a return-to pointing back here. If signed in,
   check permission: owner, member of the artifact's org (if
   `organisation`), or an `ArtifactShare` matching their email (if
   `shared`). Public artifacts never reach this endpoint at all.
3. If permitted: mint a short-lived signed token
   (`ActiveSupport::MessageVerifier`; payload = artifact id + user id +
   expiry, ~1 hour) and redirect to
   `content.mcpublish.ai/p/:slug?token=...`. The content controller
   verifies signature, expiry, and that the token names this exact slug,
   then serves the content — still no cookie, so a hosted artifact's own
   JS has nothing ambient to ride.
4. If not permitted, **or the artifact doesn't exist at all**: identical
   generic "not found" response on the main app — same parity principle as
   `update_artifact`/`delete_artifact`'s existing not-found/not-owned rule,
   so slug-probing can't distinguish "doesn't exist" from "exists but not
   shared with you."
5. Token expiry means a bookmarked gated-artifact link re-triggers the
   redirect dance on a later visit — transparent (one extra hop), not a
   hard failure, as long as the visitor is still signed in and still
   permitted.

## Error handling

- MCP tool validation errors (invalid `organization`, malformed
  `shared_with` emails) follow the existing `ToolDispatcher::ToolError`
  pattern from sub-project 1 — clean `isError: true` responses, not raw
  exceptions.
- The main app's view-authorization endpoint returns the same generic
  "not found" response for a nonexistent slug and for a real-but-forbidden
  one.
- Expired/invalid/tampered content-access tokens are treated identically to
  "no token" — redirect to the authorization flow, never a raw 403/500 on
  the content host.

## Testing approach

- Model specs: `User` (password hashing, uniqueness), `Organization`,
  `OrganizationMembership` (role enforcement), `ArtifactShare` (claiming on
  signup).
- Request specs: signup/login/logout; API key generate/revoke (scoped to
  the signed-in user, can't revoke someone else's); org create, invite,
  remove-member (admin-only enforcement); pending org-invite claiming on
  signup.
- MCP tool request specs: `publish_artifact`/`update_artifact` with each
  visibility value, including rejection of an `organization` the caller
  isn't a member of and malformed `shared_with` entries; `update_artifact`
  changing only visibility without `html`; `list_artifacts` returning
  sharing fields.
- Gated content-serving request specs: public artifact unaffected; private
  artifact — owner can view (via the redirect+token flow), a stranger gets
  the generic not-found, a signed-out visitor gets redirected to login and
  back; organisation artifact — member can view, non-member gets generic
  not-found, removing someone from the org revokes their access
  (dynamically checked, not a snapshot); shared artifact — a shared email
  with an existing account can view, an invited-but-not-yet-signed-up email
  becomes able to view immediately after signing up; token expiry triggers
  a fresh redirect rather than a hard error; a tampered/forged token is
  rejected identically to a missing one.
