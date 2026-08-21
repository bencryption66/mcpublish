# Branding, Homepage & App Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give McPublish its visual identity (page-burst tile icon + McPublish.ai wordmark), a verb-first public homepage, a site-wide BETA treatment, and a full restyle of every existing web page.

**Architecture:** One hand-written stylesheet at `public/assets/site.css` (no framework, no build step, no new gems) plus three shared partials (logo lockup, nav, footer) wired into the existing `web` layout — restyling every page at once. The homepage is a new `PagesController#home` at `root`, main-host only. All views are markup + CSS only; zero JavaScript; no behavioral changes to auth, MCP, or sharing.

**Tech Stack:** Rails 8 ERB views, vanilla CSS with custom properties, inline SVG, Google Fonts (Figtree), RSpec request specs.

## Global Constraints

- Icon geometry is canonical and fixed (from the spec): 110-viewBox ink tile `rx=26`, petal group at `translate(55,58)`, five cream petals `rect x=-6 y=-32 width=12 height=23 rx=6` rotated 60/120/180/240/300, breakaway `rect x=-6 y=-46 width=12 height=23 rx=6` fill persimmon, unrotated (top). Never re-attach the breakaway, change petal count, or fill the hollow center.
- Palette tokens exactly: ink `#23262e`, persimmon `#e8643c`, cream `#f7f1e6`, border `#e5dcc9`, muted `#6b6455`, card `#ffffff`.
- Wordmark: `McPublish.ai` — ".ai" full-size in persimmon; font stack `"Figtree", -apple-system, "Segoe UI", "Helvetica Neue", Arial, sans-serif`.
- Hero H1 exactly: `Just McPublish it.` with "McPublish" in persimmon. Sub-copy, step copy, and meta description exactly as written in the tasks below (copied from the spec).
- BETA pill site-wide in the nav: uppercase, persimmon text, 1.5px persimmon border, transparent fill, fully rounded.
- No new gems, no JS, no asset pipeline. Stylesheet linked as `/assets/site.css?v=1` (manual cache-buster).
- `content.mcpublish.ai` gains no routes: root is registered only inside the existing non-content-host constraints block.
- Existing specs assert `response.body` includes the signed-in user's email on the account page (`spec/requests/signup_spec.rb:9`, `spec/requests/login_logout_spec.rb:11`) — the restyled account page MUST keep rendering the email.
- The whole existing suite (155 examples) stays green.

---

### Task 1: Design system — icon, stylesheet, shared partials, layout

**Files:**
- Create: `public/icon.svg`
- Create: `public/assets/site.css`
- Create: `app/views/shared/_logo.html.erb`
- Create: `app/views/shared/_nav.html.erb`
- Create: `app/views/shared/_footer.html.erb`
- Modify: `app/views/layouts/web.html.erb` (full rewrite)
- Test: `spec/requests/layout_spec.rb` (new)

**Interfaces:**
- Consumes: `current_user` helper (already exposed via `helper_method` in `app/controllers/concerns/authenticatable.rb`), existing routes (`root_path` does NOT exist yet — the nav logo links to `"/"` as a literal string until Task 2 adds the route; a literal href needs no route).
- Produces (later tasks rely on these exact names):
  - Partials: `render "shared/logo", size: N` (size = tile px, default 28), `render "shared/nav"`, `render "shared/footer"`.
  - CSS classes: `container`, `site-nav`, `nav-inner`, `nav-left`, `nav-links`, `logo-lockup`, `logo-word`, `logo-ai`, `beta-pill`, `btn`, `btn-primary`, `btn-outline`, `btn-sm`, `linklike`, `flash`, `flash-notice`, `flash-alert`, `site-footer`, `footer-inner`, `footer-links`, `footer-note`, `hero`, `hero-title`, `hero-accent`, `hero-sub`, `hero-ctas`, `steps`, `step-card`, `step-num`, `examples-title`, `ex-grid`, `ex-card`, `ex-art`, `ex-bar` (+ tints `t-cream`, `t-persimmon`, `t-ink`), `ex-caption`, `page-head`, `card`, `auth-card`, `form-field`, `form-actions`, `error-list`, `row-list`, `row-item`, `row-actions`, `inline-form`, `muted`.

- [ ] **Step 1: Write the failing layout spec**

Create `spec/requests/layout_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Shared web layout", type: :request do
  it "renders the nav with the logo lockup and beta pill on public pages" do
    get "/login"

    expect(response.body).to include("site-nav")
    expect(response.body).to include("logo-lockup")
    expect(response.body).to include("beta-pill")
    expect(response.body).to include("/assets/site.css?v=1")
    expect(response.body).to include("/icon.svg")
  end

  it "shows Log in and Sign up when signed out" do
    get "/login"

    expect(response.body).to include("Sign up")
    expect(response.body).to include("nav-links")
  end

  it "shows Account and Log out when signed in" do
    User.create!(email: "nav@example.com", password: "password123", password_confirmation: "password123")
    post "/login", params: { email: "nav@example.com", password: "password123" }
    get "/account"

    expect(response.body).to include(">Account</a>")
    expect(response.body).to include("Log out")
  end

  it "renders the footer with the beta note" do
    get "/login"

    expect(response.body).to include("site-footer")
    expect(response.body).to include("things may occasionally wobble")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: FAIL — the current layout has none of these classes or links

- [ ] **Step 3: Create the icon**

Create `public/icon.svg`:

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

- [ ] **Step 4: Create the stylesheet**

Create `public/assets/site.css`:

```css
/* McPublish design system — tokens */
:root {
  --ink: #23262e;
  --persimmon: #e8643c;
  --cream: #f7f1e6;
  --border: #e5dcc9;
  --muted: #6b6455;
  --card: #ffffff;
  --font: "Figtree", -apple-system, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
}

/* base */
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: var(--font);
  background: var(--cream);
  color: var(--ink);
  line-height: 1.5;
}
a { color: var(--ink); }
h1, h2, h3 { line-height: 1.15; margin: 0 0 0.5rem; }
.container { max-width: 960px; margin: 0 auto; padding: 0 20px; }
main.container { padding-top: 32px; padding-bottom: 56px; min-height: 55vh; }
.muted { color: var(--muted); }

/* nav */
.site-nav { border-bottom: 1px solid var(--border); background: var(--cream); }
.nav-inner { display: flex; align-items: center; justify-content: space-between; padding-top: 14px; padding-bottom: 14px; }
.nav-left { display: flex; align-items: center; gap: 10px; }
.nav-left > a { text-decoration: none; }
.nav-links { display: flex; align-items: center; gap: 16px; }
.nav-links a { font-weight: 600; font-size: 0.95rem; text-decoration: none; }
.nav-links a:hover { color: var(--persimmon); }

/* logo lockup */
.logo-lockup { display: inline-flex; align-items: center; gap: 9px; }
.logo-lockup svg { display: block; }
.logo-word { font-weight: 800; letter-spacing: 0.3px; color: var(--ink); font-size: 1.15rem; }
.logo-ai { color: var(--persimmon); }

/* beta pill */
.beta-pill {
  text-transform: uppercase;
  font-size: 0.62rem;
  font-weight: 700;
  letter-spacing: 1.5px;
  color: var(--persimmon);
  border: 1.5px solid var(--persimmon);
  border-radius: 999px;
  padding: 2px 9px;
}

/* buttons */
.btn {
  display: inline-block;
  font-family: var(--font);
  font-weight: 700;
  font-size: 0.95rem;
  padding: 9px 20px;
  border-radius: 10px;
  text-decoration: none;
  border: none;
  cursor: pointer;
}
.btn-primary { background: var(--persimmon); color: #fff; }
.btn-primary:hover { filter: brightness(0.94); }
.btn-outline { background: transparent; color: var(--ink); border: 1.5px solid var(--ink); }
.btn-outline:hover { background: var(--ink); color: var(--cream); }
.btn-sm { padding: 6px 14px; font-size: 0.85rem; }
.linklike {
  background: none; border: none; padding: 0; cursor: pointer;
  font-family: var(--font); font-weight: 600; font-size: 0.95rem;
  color: var(--ink); text-decoration: underline;
}
.linklike:hover { color: var(--persimmon); }

/* flash */
.flash { padding: 10px 20px; font-weight: 600; font-size: 0.92rem; }
.flash-notice { background: var(--ink); color: var(--cream); }
.flash-alert { background: var(--persimmon); color: #fff; }

/* footer */
.site-footer { border-top: 1px solid var(--border); padding: 26px 0; }
.footer-inner { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
.footer-links { display: flex; gap: 16px; }
.footer-links a { font-size: 0.88rem; text-decoration: none; }
.footer-note { font-size: 0.82rem; color: var(--muted); }

/* homepage: hero */
.hero { text-align: center; padding: 56px 0 40px; }
.hero-title { font-size: 3.1rem; font-weight: 800; letter-spacing: -0.5px; }
.hero-accent { color: var(--persimmon); }
.hero-sub { max-width: 540px; margin: 14px auto 0; color: var(--muted); font-size: 1.1rem; }
.hero-ctas { margin-top: 26px; display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }

/* homepage: steps */
.steps { display: flex; gap: 14px; padding: 26px 0; }
.step-card {
  flex: 1;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 18px;
  font-size: 0.95rem;
}
.step-card h3 { font-size: 1rem; margin-bottom: 6px; }
.step-num { color: var(--persimmon); font-weight: 800; margin-right: 4px; }
.step-card p { margin: 0; color: var(--muted); font-size: 0.9rem; }

/* homepage: examples */
.examples-title { text-align: center; font-size: 1.5rem; margin: 40px 0 18px; }
.ex-grid { display: flex; gap: 14px; padding-bottom: 24px; }
.ex-card { flex: 1; background: var(--card); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; }
.ex-art { display: flex; gap: 6px; padding: 16px 14px; align-items: flex-end; height: 78px; }
.ex-bar { border-radius: 5px; flex: 1; }
.t-cream { background: #efe6d3; height: 55%; }
.t-persimmon { background: rgba(232, 100, 60, 0.25); height: 90%; }
.t-ink { background: rgba(35, 38, 46, 0.15); height: 70%; }
.ex-caption { padding: 0 14px 14px; font-size: 0.85rem; }
.ex-caption b { display: block; font-size: 0.92rem; }
.ex-caption span { color: var(--muted); }

/* app pages */
.page-head { margin-bottom: 20px; }
.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 22px;
  margin-bottom: 18px;
}
.auth-card { max-width: 400px; margin: 32px auto; }
.form-field { margin-bottom: 14px; }
.form-field label { display: block; font-weight: 600; font-size: 0.9rem; margin-bottom: 5px; }
.form-field input {
  width: 100%;
  padding: 9px 12px;
  border: 1.5px solid var(--border);
  border-radius: 8px;
  font-family: var(--font);
  font-size: 0.95rem;
  background: #fff;
}
.form-field input:focus { outline: none; border-color: var(--persimmon); }
.form-actions { margin-top: 18px; }
.error-list {
  background: rgba(232, 100, 60, 0.1);
  border: 1px solid var(--persimmon);
  border-radius: 8px;
  padding: 10px 14px 10px 30px;
  color: var(--ink);
  font-size: 0.9rem;
  margin: 0 0 14px;
}
.row-list { list-style: none; margin: 0; padding: 0; }
.row-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--border);
}
.row-item:last-child { border-bottom: none; }
.row-actions { display: flex; align-items: center; gap: 10px; }
.inline-form { display: flex; gap: 10px; align-items: flex-end; flex-wrap: wrap; }
.inline-form .form-field { margin-bottom: 0; flex: 1; min-width: 200px; }

/* mobile */
@media (max-width: 700px) {
  .hero-title { font-size: 2.1rem; }
  .steps, .ex-grid { flex-direction: column; }
  .nav-inner { flex-wrap: wrap; gap: 10px; }
}
```

- [ ] **Step 5: Create the logo partial**

Create `app/views/shared/_logo.html.erb`:

```erb
<% size = local_assigns.fetch(:size, 28) %>
<span class="logo-lockup">
  <svg width="<%= size %>" height="<%= size %>" viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
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
  <span class="logo-word">McPublish<span class="logo-ai">.ai</span></span>
</span>
```

- [ ] **Step 6: Create the nav partial**

Create `app/views/shared/_nav.html.erb`:

```erb
<header class="site-nav">
  <div class="container nav-inner">
    <div class="nav-left">
      <a href="/"><%= render "shared/logo" %></a>
      <span class="beta-pill">Beta</span>
    </div>
    <nav class="nav-links">
      <% if current_user %>
        <a href="<%= account_path %>">Account</a>
        <%= button_to "Log out", logout_path, method: :delete, class: "linklike" %>
      <% else %>
        <a href="<%= login_path %>">Log in</a>
        <a href="<%= signup_path %>" class="btn btn-primary btn-sm">Sign up</a>
      <% end %>
    </nav>
  </div>
</header>
```

- [ ] **Step 7: Create the footer partial**

Create `app/views/shared/_footer.html.erb`:

```erb
<footer class="site-footer">
  <div class="container footer-inner">
    <a href="/" style="text-decoration:none"><%= render "shared/logo", size: 20 %></a>
    <div class="footer-links">
      <a href="<%= login_path %>">Log in</a>
      <a href="<%= signup_path %>">Sign up</a>
    </div>
    <div class="footer-note">Beta &mdash; things may occasionally wobble. &copy; 2026 McPublish.ai</div>
  </div>
</footer>
```

- [ ] **Step 8: Rewrite the layout**

Replace the full contents of `app/views/layouts/web.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
  <head>
    <title><%= content_for(:title) || "McPublish.ai" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="description" content="Turn AI chats into live, shareable pages. Connect McPublish to your AI agent and publish anything it makes with one sentence.">
    <meta property="og:title" content="McPublish.ai — Just McPublish it">
    <meta property="og:description" content="Turn AI chats into live, shareable pages. Connect McPublish to your AI agent and publish anything it makes with one sentence.">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Figtree:wght@400;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/assets/site.css?v=1">
  </head>
  <body>
    <%= render "shared/nav" %>
    <% flash.each do |type, message| %>
      <p role="alert" class="flash <%= type.to_s == "alert" ? "flash-alert" : "flash-notice" %>"><%= message %></p>
    <% end %>
    <main class="container">
      <%= yield %>
    </main>
    <%= render "shared/footer" %>
  </body>
</html>
```

- [ ] **Step 9: Run the layout spec to verify it passes**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 10: Run the full suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 159 examples (155 + 4). If any existing spec fails, it will be a body-content assertion — check it against the Global Constraints note about preserved strings before changing anything.

- [ ] **Step 11: Commit**

```bash
git add public/icon.svg public/assets/site.css app/views/shared app/views/layouts/web.html.erb spec/requests/layout_spec.rb
git commit -m "Add McPublish design system: icon, stylesheet, nav/footer, layout"
```

---

### Task 2: Homepage

**Files:**
- Create: `app/controllers/pages_controller.rb`
- Create: `app/views/pages/home.html.erb`
- Modify: `config/routes.rb` (one line inside the non-content-host constraints block)
- Test: `spec/requests/homepage_spec.rb` (new)

**Interfaces:**
- Consumes: Task 1's layout/partials and CSS classes (`hero`, `hero-title`, `hero-accent`, `hero-sub`, `hero-ctas`, `btn btn-primary`, `btn btn-outline`, `steps`, `step-card`, `step-num`, `examples-title`, `ex-grid`, `ex-card`, `ex-art`, `ex-bar t-*`, `ex-caption`); `signup_path` (existing).
- Produces: `root_path` (used by nothing programmatically — nav/footer already link to literal `/`).

- [ ] **Step 1: Write the failing homepage spec**

Create `spec/requests/homepage_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Homepage", type: :request do
  it "renders the verb hero on the main host" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Just <span class=\"hero-accent\">McPublish</span> it.")
    expect(response.body).to include("Get started free")
    expect(response.body).to include("Things people McPublish")
  end

  it "sets the homepage title" do
    get "/"
    expect(response.body).to include("<title>McPublish.ai — Just McPublish it</title>")
  end

  it "is not routable on the content host" do
    host! "content.mcpublish.ai"
    get "/"
    expect(response).to have_http_status(:not_found)
  end

  it "shows Account in the nav when signed in" do
    User.create!(email: "home@example.com", password: "password123", password_confirmation: "password123")
    post "/login", params: { email: "home@example.com", password: "password123" }
    get "/"

    expect(response.body).to include(">Account</a>")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/homepage_spec.rb`
Expected: FAIL — no route matches `GET /` (404 on the main host too)

- [ ] **Step 3: Create the controller**

Create `app/controllers/pages_controller.rb`:

```ruby
class PagesController < WebController
  def home
  end
end
```

- [ ] **Step 4: Add the root route**

In `config/routes.rb`, inside the existing `constraints(->(req) { !on_content_host.call(req) }) do ... end` block, add as its first line (above the health check):

```ruby
    root "pages#home"
```

- [ ] **Step 5: Create the homepage view**

Create `app/views/pages/home.html.erb`:

```erb
<% content_for :title, "McPublish.ai — Just McPublish it" %>

<section class="hero">
  <h1 class="hero-title">Just <span class="hero-accent">McPublish</span> it.</h1>
  <p class="hero-sub">Your AI builds something great. McPublish puts it on the web &mdash; a live, shareable page from one sentence. No deploys, no copy-paste.</p>
  <div class="hero-ctas">
    <a href="<%= signup_path %>" class="btn btn-primary">Get started free</a>
    <a href="#how" class="btn btn-outline">See how it works</a>
  </div>
</section>

<section id="how" class="steps">
  <div class="step-card">
    <h3><span class="step-num">1.</span>Connect</h3>
    <p>Add McPublish to Claude or any MCP-enabled AI. Two minutes, once.</p>
  </div>
  <div class="step-card">
    <h3><span class="step-num">2.</span>Say &ldquo;McPublish that&rdquo;</h3>
    <p>Your agent publishes what it just made.</p>
  </div>
  <div class="step-card">
    <h3><span class="step-num">3.</span>Share the live link</h3>
    <p>A real page on the web, private by default, shareable when you say so.</p>
  </div>
</section>

<section>
  <h2 class="examples-title">Things people McPublish</h2>
  <div class="ex-grid">
    <div class="ex-card">
      <div class="ex-art">
        <div class="ex-bar t-cream"></div>
        <div class="ex-bar t-persimmon"></div>
        <div class="ex-bar t-ink"></div>
      </div>
      <div class="ex-caption"><b>Dashboards</b><span>Live charts straight from a chat.</span></div>
    </div>
    <div class="ex-card">
      <div class="ex-art">
        <div class="ex-bar t-ink" style="height:30%"></div>
        <div class="ex-bar t-ink" style="height:30%"></div>
        <div class="ex-bar t-ink" style="height:30%"></div>
      </div>
      <div class="ex-caption"><b>Reports</b><span>Polished write-ups, instantly shareable.</span></div>
    </div>
    <div class="ex-card">
      <div class="ex-art">
        <div class="ex-bar t-cream" style="height:100%"></div>
        <div class="ex-bar t-persimmon" style="height:100%"></div>
      </div>
      <div class="ex-caption"><b>Comparison tables</b><span>Side-by-sides that settle it.</span></div>
    </div>
    <div class="ex-card">
      <div class="ex-art">
        <div class="ex-bar t-persimmon" style="height:60%"></div>
        <div class="ex-bar t-cream" style="height:85%"></div>
        <div class="ex-bar t-ink" style="height:45%"></div>
      </div>
      <div class="ex-caption"><b>Mini-apps</b><span>Tiny tools that just work.</span></div>
    </div>
  </div>
</section>
```

- [ ] **Step 6: Run the homepage spec to verify it passes**

Run: `bundle exec rspec spec/requests/homepage_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 7: Run the full suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 163 examples

- [ ] **Step 8: Commit**

```bash
git add app/controllers/pages_controller.rb app/views/pages config/routes.rb spec/requests/homepage_spec.rb
git commit -m "Add verb-hero homepage at root on the main host"
```

---

### Task 3: Restyle the existing app pages

**Files:**
- Modify: `app/views/sessions/new.html.erb` (full rewrite)
- Modify: `app/views/users/new.html.erb` (full rewrite)
- Modify: `app/views/account/show.html.erb` (full rewrite)
- Modify: `app/views/api_keys/index.html.erb` (full rewrite)
- Modify: `app/views/organizations/index.html.erb` (full rewrite)
- Modify: `app/views/organizations/new.html.erb` (full rewrite)
- Modify: `app/views/organizations/show.html.erb` (full rewrite)
- Test: `spec/requests/layout_spec.rb` (additions)

**Interfaces:**
- Consumes: Task 1's CSS classes (`auth-card`, `card`, `page-head`, `form-field`, `form-actions`, `error-list`, `row-list`, `row-item`, `row-actions`, `inline-form`, `btn`, `btn-primary`, `btn-outline`, `btn-sm`, `linklike`, `muted`).
- Produces: nothing consumed later. Behavioral invariants: all form URLs/methods/params identical to current views; account page still renders `Signed in as <email>` (specs depend on the email appearing in the body); the account page's duplicate "Log out" button is removed (the nav now owns logout).

- [ ] **Step 1: Write the failing spec additions**

Add to `spec/requests/layout_spec.rb`, inside the existing describe block:

```ruby
  it "renders the signup page as an auth card with the verb heading" do
    get "/signup"

    expect(response.body).to include("Start McPublishing")
    expect(response.body).to include("auth-card")
  end

  it "renders the login page as an auth card" do
    get "/login"

    expect(response.body).to include("auth-card")
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: FAIL — the two new examples (current pages have neither string)

- [ ] **Step 3: Rewrite the login page**

Replace the full contents of `app/views/sessions/new.html.erb`:

```erb
<div class="card auth-card">
  <h1>Log in</h1>

  <%= form_with url: login_path, local: true do |f| %>
    <div class="form-field">
      <%= f.label :email %>
      <%= f.email_field :email %>
    </div>
    <div class="form-field">
      <%= f.label :password %>
      <%= f.password_field :password %>
    </div>
    <div class="form-actions">
      <%= f.submit "Log in", class: "btn btn-primary", style: "width:100%" %>
    </div>
  <% end %>

  <p class="muted">New here? <%= link_to "Sign up", signup_path %></p>
</div>
```

- [ ] **Step 4: Rewrite the signup page**

Replace the full contents of `app/views/users/new.html.erb`:

```erb
<div class="card auth-card">
  <h1>Start McPublishing</h1>
  <p class="muted">Free while we&rsquo;re in beta.</p>

  <% if @user.errors.any? %>
    <ul role="alert" class="error-list">
      <% @user.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  <% end %>

  <%= form_with model: @user, url: signup_path, local: true do |f| %>
    <div class="form-field">
      <%= f.label :email %>
      <%= f.email_field :email %>
    </div>
    <div class="form-field">
      <%= f.label :password %>
      <%= f.password_field :password %>
    </div>
    <div class="form-field">
      <%= f.label :password_confirmation %>
      <%= f.password_field :password_confirmation %>
    </div>
    <div class="form-actions">
      <%= f.submit "Sign up", class: "btn btn-primary", style: "width:100%" %>
    </div>
  <% end %>

  <p class="muted">Already have an account? <%= link_to "Log in", login_path %></p>
</div>
```

- [ ] **Step 5: Rewrite the account page**

Replace the full contents of `app/views/account/show.html.erb`:

```erb
<div class="page-head">
  <h1>Account</h1>
  <p class="muted">Signed in as <%= current_user.email %></p>
</div>

<div class="card">
  <h3>API keys</h3>
  <p class="muted">Keys your AI agents use to McPublish on your behalf.</p>
  <%= link_to "Manage API keys", api_keys_path, class: "btn btn-outline btn-sm" %>
</div>

<div class="card">
  <h3>Organizations</h3>
  <p class="muted">Share artifacts with your team.</p>
  <%= link_to "Manage organizations", organizations_path, class: "btn btn-outline btn-sm" %>
</div>
```

- [ ] **Step 6: Rewrite the API keys page**

Replace the full contents of `app/views/api_keys/index.html.erb`:

```erb
<div class="page-head">
  <h1>API keys</h1>
</div>

<div class="card">
  <ul class="row-list">
    <% @api_keys.each do |api_key| %>
      <li class="row-item">
        <span><%= api_key.label %><% if api_key.revoked? %> <span class="muted">(revoked)</span><% end %></span>
        <% unless api_key.revoked? %>
          <span class="row-actions">
            <%= button_to "Revoke", api_key_path(api_key), method: :delete, class: "linklike" %>
          </span>
        <% end %>
      </li>
    <% end %>
  </ul>
</div>

<div class="card">
  <%= form_with url: api_keys_path, local: true, class: "inline-form" do |f| %>
    <div class="form-field">
      <%= f.label :label, "New key label" %>
      <%= f.text_field :label %>
    </div>
    <%= f.submit "Generate key", class: "btn btn-primary" %>
  <% end %>
</div>
```

- [ ] **Step 7: Rewrite the organizations pages**

Replace the full contents of `app/views/organizations/index.html.erb`:

```erb
<div class="page-head">
  <h1>Your organizations</h1>
</div>

<div class="card">
  <ul class="row-list">
    <% @organizations.each do |org| %>
      <li class="row-item"><%= link_to org.name, organization_path(org) %></li>
    <% end %>
  </ul>
</div>

<%= link_to "New organization", new_organization_path, class: "btn btn-primary" %>
```

Replace the full contents of `app/views/organizations/new.html.erb`:

```erb
<div class="card auth-card">
  <h1>New organization</h1>

  <% if @organization.errors.any? %>
    <ul role="alert" class="error-list">
      <% @organization.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  <% end %>

  <%= form_with model: @organization, url: organizations_path, local: true do |f| %>
    <div class="form-field">
      <%= f.label :name %>
      <%= f.text_field :name %>
    </div>
    <div class="form-field">
      <%= f.label :slug %>
      <%= f.text_field :slug %>
    </div>
    <div class="form-actions">
      <%= f.submit "Create", class: "btn btn-primary", style: "width:100%" %>
    </div>
  <% end %>
</div>
```

Replace the full contents of `app/views/organizations/show.html.erb`:

```erb
<div class="page-head">
  <h1><%= @organization.name %></h1>
</div>

<div class="card">
  <ul class="row-list">
    <% @memberships.each do |membership| %>
      <li class="row-item">
        <span><%= membership.user.email %> <span class="muted">(<%= membership.role %>)</span></span>
        <span class="row-actions">
          <%= button_to "Remove", remove_member_organization_path(@organization, membership_id: membership.id), method: :delete, class: "linklike" %>
        </span>
      </li>
    <% end %>
  </ul>
</div>

<div class="card">
  <%= form_with url: invite_organization_path(@organization), method: :post, local: true, class: "inline-form" do |f| %>
    <div class="form-field">
      <%= f.label :email, "Invite by email" %>
      <%= f.email_field :email %>
    </div>
    <%= f.submit "Invite", class: "btn btn-primary" %>
  <% end %>
</div>
```

- [ ] **Step 8: Run the layout spec to verify the new examples pass**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 9: Run the full suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 165 examples. Watch `spec/requests/signup_spec.rb` and `spec/requests/login_logout_spec.rb` in particular — both assert the account page body includes the user's email, which "Signed in as" preserves.

- [ ] **Step 10: Commit**

```bash
git add app/views spec/requests/layout_spec.rb
git commit -m "Restyle auth, account, API keys, and organizations pages"
```
