# Artifact Promo Banner — Design

Decided 2026-08-21. Mockups preserved in `.superpowers/brainstorm/610-1787482525/content/banner-copy.html` (chosen option: A, "verb-forward").

## Goal

Every artifact served from `content.mcpublish.ai` carries a sticky McPublish banner at the top: logo, a line of verb-forward copy, and a signup CTA. It is the product's main organic growth surface — when someone shares a McPublished page, the recipient learns what McPublish is and how to get it.

## 1. The banner

Sticky bar, 44px tall, ink (`#23262e`) background with cream (`#f7f1e6`) text, pinned to the top of the viewport.

Contents, left to right:

1. The page-burst icon (cream tile variant — cream rounded square, ink petals, persimmon breakaway) at 20px, plus the wordmark `McPublish.ai` (".ai" in persimmon `#e8643c`), together linking to `https://mcpublish.ai`.
2. Copy: `This page was **McPublished** straight from an AI chat.` — "McPublished" bold in cream, the rest in muted `#bdb4a2`.
3. A persimmon CTA button reading `McPublish your own →`, linking to `https://mcpublish.ai/signup`.

Both links use `target="_blank" rel="noopener"` so a visitor reading an artifact does not lose it.

Applies to **all artifacts regardless of visibility** — public, organisation, shared, and private alike.

### Copy is deliberately client-agnostic

McPublish does not record which MCP client published an artifact (any client can call the API with a valid key), so the banner says "an AI chat" rather than naming a specific product. Naming a client would require storing `clientInfo.name` from the MCP `initialize` handshake — explicitly out of scope here (see Non-goals).

### The content host still has no session

`ContentController` has no session access by architectural rule, so the banner cannot know who is viewing. Every visitor sees identical copy, including signed-in McPublish users viewing their own private artifacts. This is accepted, not a defect.

## 2. Where it is built

New service `app/services/artifact_banner.rb`:

```ruby
ArtifactBanner.inject(html) # => html with the banner markup + styles inserted
```

`ContentController#serve` calls it between the S3 fetch and `render`. Two consequences:

- **The stored artifact is never modified.** Injection is serve-time only; the S3 object and the artifact's `byte_size` remain exactly as the agent published them.
- `ContentController` stays thin; the banner is unit-testable without HTTP.

### Injection rule

Insert immediately after the first `<body …>` tag when one exists; otherwise prepend to the document. Agents produce both full documents and bare fragments, so both must work. The match must be case-insensitive and tolerate attributes on the tag (`<body class="x">`).

## 3. Surviving arbitrary artifact CSS

Artifacts are AI-generated HTML containing any CSS, including rules like `div { font-size: 40px }` that would wreck a naively-injected banner. Defenses:

- All banner styles live in one injected `<style>` block scoped to `#mcpublish-banner`, with `!important` on every declaration. ID selector + `!important` outranks essentially anything an artifact declares.
- `position: fixed` with `z-index: 2147483647`. `position: sticky` would be cleaner (it occupies flow space, no padding hack) but silently fails inside artifacts that scroll an inner container rather than the body — common in AI-generated full-page apps. Fixed always pins.
- Because fixed elements reserve no space, the style block also sets `html { padding-top: 44px !important }`. Accepted tradeoff: an artifact built to exactly `100vh` gains 44px of scroll — preferable to covering its content.
- A `max-width: 640px` media query hides the middle sentence, leaving logo + CTA.

**Known limit:** a deliberately hostile artifact can still hide the banner with `#mcpublish-banner { display: none !important }`. Bulletproofing requires shadow DOM or an iframe wrapper; both cost more than they are worth for a growth banner. This is the same tradeoff comparable hosting products accept.

## 4. Testing

Request specs against the content host:

- Banner present on a public artifact.
- Banner present on a token-served private artifact.
- The artifact's own markup survives injection intact.
- Links point at `https://mcpublish.ai` and `https://mcpublish.ai/signup`.
- Injection lands after `<body>` when present, and still works on a bare fragment with no `<body>`.
- **No `Set-Cookie` on a banner-carrying response** — this is the first time the content host serves markup McPublish authored, so the session-isolation invariant gets an explicit test at this new surface.

Service specs for `ArtifactBanner.inject` covering the body-tag and fragment branches directly.

## Non-goals

- Dismissibility, and any JavaScript at all.
- Per-client attribution ("McPublished from Claude Code") — would require storing `clientInfo.name` from the MCP handshake.
- Analytics or click tracking on the banner.
- Any change to how artifacts are stored, gated, or authorized.
