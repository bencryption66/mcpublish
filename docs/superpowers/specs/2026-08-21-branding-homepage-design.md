# McPublish Branding, Homepage & App Restyle — Design

Decided 2026-08-21 through visual brainstorming (mockup files preserved in `.superpowers/brainstorm/73546-1787314223/content/`; the chosen mark is variation 4 in `logo-burst-variations.html`, the chosen wordmark is option B in `logo-wordmark-variations.html`, the chosen homepage is option A in `homepage-layouts.html`).

## Goals

- Give McPublish a real visual identity: an ownable icon usable standalone (favicon, avatar) plus a wordmark lockup reading **McPublish.ai**.
- A public homepage that pitches the product to general AI power users and pushes **McPublish as a verb** ("Just McPublish it").
- Communicate clearly that the product is in **beta**.
- Restyle every existing web page (login, signup, account, API keys, organizations) with the same design system.

## 1. Brand identity

### 1.1 Icon — "page burst" app tile

An ink rounded-square tile containing six rounded "pages" radiating from a hollow center; five are cream and in place, the sixth (top) is persimmon and lifted away from the ring — a freshly published page breaking out.

Canonical geometry (the source of truth for all renderings):

```svg
<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="110" height="110" rx="26" fill="#23262e"/>
  <g transform="translate(55,58)">
    <g fill="#f7f1e6">
      <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(60)"/>
      <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(120)"/>
      <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(180)"/>
      <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(240)"/>
      <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(300)"/>
    </g>
    <rect x="-6" y="-46" width="12" height="23" rx="6" fill="#e8643c"/>
  </g>
</svg>
```

Rules:
- The tile version is the standalone icon (favicon `public/icon.svg`, avatars, app contexts).
- A tile-less version (same petals, ink petals on cream, persimmon breakaway) may be used inline on cream surfaces where a dark tile would be heavy — same geometry, colors swapped.
- The petal group sits slightly below tile center (`translate(55,58)` on a 110 tile) so the lifted breakaway reads visually balanced.
- Never re-attach the breakaway, change petal count, or fill the hollow center.

### 1.2 Wordmark

- Text: `McPublish.ai` — capital M and P; ".ai" is part of the name, set at **full size**.
- Font: **Figtree** ExtraBold (800) with system fallback: `"Figtree", -apple-system, "Segoe UI", "Helvetica Neue", Arial, sans-serif`. Slight positive letter-spacing (~0.3px at nav size).
- Color: "McPublish" in ink `#23262e`; ".ai" in persimmon `#e8643c`. On dark surfaces: "McPublish" in cream, ".ai" stays persimmon.

### 1.3 Lockups

- **Horizontal** (default: nav, footer): tile icon at cap-height-plus, 8–10px gap, wordmark.
- **Stacked** (square contexts: social cards, splash): tile centered above wordmark; optional small letter-spaced "BETA" line beneath.

### 1.4 Palette

| Token | Hex | Use |
|---|---|---|
| ink | `#23262e` | tile, headings, body text, primary dark surfaces |
| persimmon | `#e8643c` | accent, ".ai", breakaway petal, primary CTA, BETA pill |
| cream | `#f7f1e6` | page background, petals on tile |
| border | `#e5dcc9` | card borders, dividers on cream |
| muted | `#6b6455` | secondary text on cream |
| card | `#ffffff` | card backgrounds on cream |

### 1.5 Beta treatment

A pill beside the wordmark in the site nav, on every page: text "BETA", uppercase, ~10px, weight 700, letter-spaced, persimmon text with a 1.5px persimmon border, transparent fill, fully rounded. The footer carries the softer line "Beta — things may occasionally wobble."

### 1.6 Voice

Playful and punchy; McPublish used as a verb wherever it reads naturally ("McPublish that", "Get McPublishing", "Things people McPublish"). Never robotic ("utilize the McPublish platform"), never more than roughly one verb-usage per screen section — the joke should land, not grate.

## 2. Homepage

### 2.1 Routing

- `root "pages#home"` inside the existing `constraints(->(req) { !on_content_host.call(req) })` block in `config/routes.rb`. The content host gains no root route (falls through to 404), preserving the rule that `content.mcpublish.ai` serves only `/p/:slug`.
- New `PagesController < WebController` with a single `home` action (needs `current_user` for nav state; no login requirement).

### 2.2 Page structure & copy (top to bottom)

1. **Nav** — left: horizontal lockup + BETA pill (links to `/`); right, signed out: "Log in" text link + "Sign up" ink button; signed in: "Account" link + "Log out".
2. **Hero** (centered):
   - H1: `Just McPublish it.` — "McPublish" in persimmon.
   - Sub: `Your AI builds something great. McPublish puts it on the web — a live, shareable page from one sentence. No deploys, no copy-paste.`
   - CTAs: **Get started free** (persimmon button → `/signup`) and **See how it works** (ink outline button → `#how`).
3. **3-step strip** (`id="how"`, three cards):
   - `1. Connect` — Add McPublish to Claude or any MCP-enabled AI. Two minutes, once.
   - `2. Say "McPublish that"` — Your agent publishes what it just made.
   - `3. Share the live link` — A real page on the web, private by default, shareable when you say so.
4. **Examples strip** — heading `Things people McPublish`, four small stylized cards rendered in CSS/inline-SVG (no screenshots): Dashboard, Report, Comparison table, Mini-app. Each card is decorative (abstract blocks in palette colors) with a one-line caption.
5. **Footer** — slim, cream with top border: horizontal lockup (small), links Log in / Sign up, the beta line, `© 2026 McPublish.ai`.

### 2.3 Meta

`<title>McPublish.ai — Just McPublish it</title>`, meta description (`Turn AI chats into live, shareable pages. Connect McPublish to your AI agent and publish anything it makes with one sentence.`), `og:title`, `og:description`, favicon link to `/icon.svg`. og:image is an explicit non-goal for now (follow-up).

## 3. App restyle

### 3.1 Shared layout (`app/views/layouts/web.html.erb`)

- `<head>`: title, viewport, Google Fonts link for Figtree (400/600/700/800), stylesheet link to `/assets/site.css?v=1`, favicon.
- `<body>`: nav partial → styled flash messages (cream-on-ink toast-style bars, persimmon for alerts) → `<main class="container">` yield → footer partial.
- Partials: `app/views/shared/_nav.html.erb`, `app/views/shared/_footer.html.erb`, `app/views/shared/_logo.html.erb` (inline SVG lockup; accepts a size variant).
- The homepage uses the same layout; its hero/sections are page content, not layout.

### 3.2 Page-level restyle

All existing views restyled with shared CSS classes (cards, buttons, forms, tables) — no structural/behavioral changes, no JS:

- `sessions/new` & `users/new`: centered auth card (~400px), labeled inputs, full-width persimmon submit. Signup heading: "Start McPublishing". Cross-links between the two.
- `account/show`: heading + cards matching the system.
- `api_keys/index`: card-wrapped table, styled create form, revoke as quiet destructive-styled button.
- `organizations/index|new|show`: same card/table/form treatment.
- Flash messages: notice = ink bar, alert = persimmon bar.

### 3.3 CSS

- One hand-written stylesheet: `public/assets/site.css`. No framework, no build step, no new gems.
- Cache busting is manual: bump the `?v=N` query param in the layout whenever the file changes (production serves `public/` with 1-year cache headers).
- Design tokens as CSS custom properties on `:root` (the palette table above).
- Mobile: single breakpoint (~700px) — nav wraps, hero type scales down, step/example cards stack.

## 4. Assets

- `public/icon.svg` — the tile icon (canonical SVG above).
- `app/views/shared/_logo.html.erb` — inline horizontal lockup.
- No PNG/ICO favicons, no og-image, no additional logo files for now.

## 5. Testing

Request specs (model/service layers untouched):

- `GET /` on the main host → 200, body contains "Just McPublish it".
- `GET /` on `content.mcpublish.ai` → 404.
- Homepage nav shows "Sign up" when signed out and "Account" when signed in.
- Full existing suite (155 examples) stays green — the restyle adds markup/CSS but changes no behavior; any existing spec asserting on view content is updated only if the restyle moved the asserted text.

## Non-goals

- og:image / social preview image generation.
- PNG/ICO favicon fallbacks.
- Dark mode.
- Restyling artifact content pages (`content.mcpublish.ai` serves raw artifact HTML untouched).
- Any change to MCP tools, auth flows, or sharing behavior.
