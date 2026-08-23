# Artifact Promo Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject a sticky McPublish banner (logo, verb-forward copy, signup CTA) at the top of every artifact served from `content.mcpublish.ai`.

**Architecture:** A single `ArtifactBanner` service builds the banner markup and inserts it into artifact HTML at serve time; `ContentController#serve` calls it between the S3 fetch and `render`. The stored artifact is never modified. All banner CSS is scoped to `#mcpublish-banner` with `!important` so arbitrary artifact CSS cannot restyle it, and the banner ships zero JavaScript.

**Tech Stack:** Plain Ruby (no new gems), inline `<style>` + `<div>` markup, RSpec service and request specs.

## Global Constraints

- Banner appears on **all artifacts regardless of visibility** — public, organisation, shared, and private alike.
- Injection is **serve-time only**: the S3 object and the artifact's `byte_size` are never modified.
- **No JavaScript.** No external requests of any kind (no Google Fonts link) — the banner uses a system font stack only.
- Copy is exactly: `This page was <b>McPublished</b> straight from an AI chat.` — client-agnostic on purpose; never name a specific AI product.
- CTA reads exactly `McPublish your own →` and links to `/signup` on the main host. The brand lockup links to the main host root. Both links carry `target="_blank" rel="noopener"`.
- Colors exactly: ink `#23262e` (background), cream `#f7f1e6` (brand text), muted `#bdb4a2` (copy), persimmon `#e8643c` (".ai", breakaway petal, CTA background), white `#ffffff` (CTA text).
- Banner is `position: fixed`, `height: 44px`, `z-index: 2147483647`; the style block also sets `html { padding-top: 44px !important }` to reserve the strip.
- Every banner declaration carries `!important` and is scoped under `#mcpublish-banner` (or the `html` rule above). No unscoped selectors — the banner must never restyle the artifact.
- A `max-width: 640px` media query hides the middle copy, leaving brand + CTA.
- Icon geometry is the canonical page-burst mark, cream-tile variant: `viewBox="0 0 110 110"`, tile `rx="26"` fill `#f7f1e6`, petal group at `translate(55,58)`, five ink (`#23262e`) petals `rect x="-6" y="-32" width="12" height="23" rx="6"` rotated 60/120/180/240/300, breakaway `rect x="-6" y="-46" width="12" height="23" rx="6"` fill `#e8643c`, unrotated.
- `ContentController` must never gain session access — this plan does not touch its `session` guard and adds no cookie logic.
- Host is read from `Rails.application.config.x.main_host` (never hardcoded), matching how the rest of the app builds cross-host URLs.
- No new gems. The whole existing suite (173 examples) stays green.

---

### Task 1: The ArtifactBanner service

**Files:**
- Create: `app/services/artifact_banner.rb`
- Test: `spec/services/artifact_banner_spec.rb` (new)

**Interfaces:**
- Consumes: `Rails.application.config.x.main_host` (existing, set in `config/initializers/content_host.rb`; defaults to `"mcpublish.ai"`).
- Produces: `ArtifactBanner.inject(html)` → `String` — the same HTML with the banner's `<style>` block and `<div id="mcpublish-banner">` inserted. Task 2 calls exactly this. Nothing else in the class is public API.

- [ ] **Step 1: Write the failing service spec**

Create `spec/services/artifact_banner_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ArtifactBanner do
  describe ".inject" do
    it "inserts the banner immediately after the body tag" do
      result = described_class.inject("<html><body><h1>Hi</h1></body></html>")

      expect(result).to start_with("<html><body>")
      expect(result).to include('<div id="mcpublish-banner"')
      expect(result.index("mcpublish-banner")).to be < result.index("<h1>Hi</h1>")
    end

    it "handles a body tag carrying attributes" do
      result = described_class.inject(%(<html><body class="dark" data-x="1"><p>Yo</p></body></html>))

      expect(result).to include(%(<body class="dark" data-x="1">))
      expect(result).to include('<div id="mcpublish-banner"')
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Yo</p>")
    end

    it "matches an uppercase body tag" do
      result = described_class.inject("<HTML><BODY><p>Yo</p></BODY></HTML>")

      expect(result).to include('<div id="mcpublish-banner"')
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Yo</p>")
    end

    it "prepends the banner to a bare fragment with no body tag" do
      result = described_class.inject("<h1>Just a fragment</h1>")

      expect(result).to start_with("<style")
      expect(result).to include("<h1>Just a fragment</h1>")
    end

    it "never inserts anything before a doctype" do
      result = described_class.inject("<!DOCTYPE html><html><head></head></html>")

      expect(result).to start_with("<!DOCTYPE html>")
      expect(result).to include('<div id="mcpublish-banner"')
    end

    it "preserves the artifact's original content verbatim" do
      original = "<html><body><h1>Q3 Sales</h1><p>Revenue up 12%.</p></body></html>"

      expect(described_class.inject(original)).to include("<h1>Q3 Sales</h1><p>Revenue up 12%.</p>")
    end

    it "links the brand to the main host and the CTA to signup" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include(%(href="https://mcpublish.ai" target="_blank" rel="noopener"))
      expect(result).to include(%(href="https://mcpublish.ai/signup" target="_blank" rel="noopener"))
    end

    it "builds links from the configured main host rather than a hardcoded domain" do
      original_main_host = Rails.application.config.x.main_host
      Rails.application.config.x.main_host = "example.test"

      result = described_class.inject("<html><body></body></html>")

      expect(result).to include(%(href="https://example.test"))
      expect(result).to include(%(href="https://example.test/signup"))
    ensure
      Rails.application.config.x.main_host = original_main_host
    end

    it "carries the exact approved copy and CTA" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include("This page was <b>McPublished</b> straight from an AI chat.")
      expect(result).to include("McPublish your own &rarr;")
    end

    it "reserves space for the fixed banner and scopes every rule" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include("html{padding-top:44px !important}")
      expect(result).to include("position:fixed !important")
      expect(result).to include("z-index:2147483647 !important")
      expect(result).to include("@media (max-width:640px)")
    end

    it "ships no javascript" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).not_to include("<script")
      expect(result).not_to include("onclick")
    end

    it "returns the input unchanged when it is blank" do
      expect(described_class.inject("")).to eq("")
      expect(described_class.inject(nil)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/services/artifact_banner_spec.rb`
Expected: FAIL — `uninitialized constant ArtifactBanner`

- [ ] **Step 3: Write the service**

Create `app/services/artifact_banner.rb`:

```ruby
# Injects the McPublish promo banner into artifact HTML at serve time.
#
# The stored artifact is never modified — this runs on the way out of
# ContentController#serve, so the S3 object and the artifact's byte_size
# stay exactly as the publishing agent wrote them.
#
# Artifacts are arbitrary AI-generated HTML and may carry any CSS, so every
# declaration below is scoped to #mcpublish-banner and marked !important:
# an ID selector plus !important outranks essentially anything an artifact
# declares. A deliberately hostile artifact can still hide the banner with
# its own !important rule; defending against that needs shadow DOM or an
# iframe wrapper, which costs more than it is worth for a promo banner.
class ArtifactBanner
  BODY_TAG = /<body\b[^>]*>/i
  DOCTYPE = /\A\s*<!doctype[^>]*>/i

  # position:fixed rather than sticky: sticky silently fails inside artifacts
  # that scroll an inner container instead of the body, which is common in
  # AI-generated full-page apps. Fixed always pins, so the html padding-top
  # below reserves the strip the banner would otherwise cover.
  STYLE = <<~'CSS'.gsub(/\s*\n\s*/, "").freeze
    <style id="mcpublish-banner-style">
    html{padding-top:44px !important}
    #mcpublish-banner{position:fixed !important;top:0 !important;left:0 !important;right:0 !important;z-index:2147483647 !important;box-sizing:border-box !important;height:44px !important;display:flex !important;align-items:center !important;gap:10px !important;margin:0 !important;padding:0 14px !important;background:#23262e !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Helvetica Neue",Arial,sans-serif !important;font-size:13px !important;line-height:1 !important;text-align:left !important;text-transform:none !important;letter-spacing:normal !important;visibility:visible !important;opacity:1 !important;transform:none !important}
    #mcpublish-banner *{box-sizing:border-box !important;margin:0 !important;padding:0 !important;text-transform:none !important;letter-spacing:normal !important}
    #mcpublish-banner a{text-decoration:none !important}
    #mcpublish-banner .mcpb-brand{display:inline-flex !important;align-items:center !important;gap:7px !important;flex:0 0 auto !important;color:#f7f1e6 !important;font-size:13px !important;font-weight:800 !important}
    #mcpublish-banner svg{display:block !important;width:20px !important;height:20px !important;flex:0 0 auto !important}
    #mcpublish-banner .mcpb-ai{color:#e8643c !important}
    #mcpublish-banner .mcpb-copy{flex:1 1 auto !important;min-width:0 !important;color:#bdb4a2 !important;font-size:12.5px !important;font-weight:400 !important;white-space:nowrap !important;overflow:hidden !important;text-overflow:ellipsis !important}
    #mcpublish-banner .mcpb-copy b{color:#f7f1e6 !important;font-weight:700 !important}
    #mcpublish-banner .mcpb-cta{flex:0 0 auto !important;background:#e8643c !important;color:#ffffff !important;font-size:11.5px !important;font-weight:700 !important;padding:6px 12px !important;border-radius:7px !important}
    @media (max-width:640px){#mcpublish-banner .mcpb-copy{display:none !important}#mcpublish-banner .mcpb-brand{flex:1 1 auto !important}}
    </style>
  CSS

  ICON = <<~'SVG'.gsub(/\s*\n\s*/, "").freeze
    <svg viewBox="0 0 110 110" aria-hidden="true">
    <rect width="110" height="110" rx="26" fill="#f7f1e6"/>
    <g transform="translate(55,58)">
    <g fill="#23262e">
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(60)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(120)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(180)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(240)"/>
    <rect x="-6" y="-32" width="12" height="23" rx="6" transform="rotate(300)"/>
    </g>
    <rect x="-6" y="-46" width="12" height="23" rx="6" fill="#e8643c"/>
    </g>
    </svg>
  SVG

  class << self
    def inject(html)
      return html if html.blank?

      markup = STYLE + banner_div

      return html.sub(BODY_TAG) { |tag| tag + markup } if html.match?(BODY_TAG)
      return html.sub(DOCTYPE) { |doctype| doctype + markup } if html.match?(DOCTYPE)

      markup + html
    end

    private

    # Built per call rather than frozen at load time so the host always
    # reflects the current config (the same reason Artifact#url reads it
    # each call). Only this small div is dynamic; the CSS is a constant.
    def banner_div
      host = "https://#{Rails.application.config.x.main_host}"

      <<~HTML.gsub(/\s*\n\s*/, "")
        <div id="mcpublish-banner">
        <a class="mcpb-brand" href="#{host}" target="_blank" rel="noopener">#{ICON}<span>McPublish<span class="mcpb-ai">.ai</span></span></a>
        <span class="mcpb-copy">This page was <b>McPublished</b> straight from an AI chat.</span>
        <a class="mcpb-cta" href="#{host}/signup" target="_blank" rel="noopener">McPublish your own &rarr;</a>
        </div>
      HTML
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/artifact_banner_spec.rb`
Expected: PASS (12 examples)

- [ ] **Step 5: Run the full suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 185 examples (173 + 12). Nothing calls `ArtifactBanner` yet, so no existing example changes behavior.

- [ ] **Step 6: Commit**

```bash
git add app/services/artifact_banner.rb spec/services/artifact_banner_spec.rb
git commit -m "Add ArtifactBanner service for serve-time promo banner injection"
```

---

### Task 2: Serve the banner with every artifact

**Files:**
- Modify: `app/controllers/content_controller.rb` (the `serve` private method only)
- Modify: `spec/requests/content_spec.rb`

**Interfaces:**
- Consumes: `ArtifactBanner.inject(html)` → `String` (Task 1).
- Produces: nothing consumed later. Behavioral change: every 200 response from `GET content.mcpublish.ai/p/:slug` now contains the banner markup ahead of the artifact's own content.

- [ ] **Step 1: Update the two existing body assertions and add the banner examples**

Two existing examples in `spec/requests/content_spec.rb` assert the response body **equals** the stored HTML exactly; the banner makes that false. Change both from `eq` to `include`, then add coverage for the banner itself.

In `spec/requests/content_spec.rb`, in the "serves the artifact's html" example, change:

```ruby
    expect(response.body).to eq("<html>hello</html>")
```

to:

```ruby
    expect(response.body).to include("<html>hello</html>")
```

In the "serves a private artifact when a valid token is given" example, change:

```ruby
    expect(response.body).to eq("<html>hello</html>")
```

to:

```ruby
    expect(response.body).to include("<html>hello</html>")
```

Then add these examples inside the same `RSpec.describe` block:

```ruby
  it "injects the McPublish banner above a public artifact" do
    get "/p/#{artifact.slug}"

    expect(response.body).to include('<div id="mcpublish-banner"')
    expect(response.body).to include("This page was <b>McPublished</b> straight from an AI chat.")
    expect(response.body).to include(%(href="https://mcpublish.ai/signup"))
  end

  it "injects the banner on a token-served private artifact too" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")
    token = ContentAccessToken.generate(artifact: private_artifact, user: user)

    get "/p/#{private_artifact.slug}", params: { token: token }

    expect(response.body).to include('<div id="mcpublish-banner"')
  end

  it "sets no Set-Cookie header on a banner-carrying response" do
    get "/p/#{artifact.slug}"

    expect(response.body).to include('<div id="mcpublish-banner"')
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "leaves the stored artifact untouched" do
    expect {
      get "/p/#{artifact.slug}"
    }.not_to change { artifact.reload.byte_size }
  end
```

- [ ] **Step 2: Run the spec to verify the new examples fail**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: FAIL — the three banner examples fail (no banner in the body). The two `include` edits and the `byte_size` example already pass, since `include` is satisfied by the un-injected body today.

- [ ] **Step 3: Wire the banner into serving**

In `app/controllers/content_controller.rb`, replace the `serve` method:

```ruby
  def serve(artifact)
    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: ArtifactBanner.inject(html), content_type: "text/html"
  end
```

Leave the rest of the file — including the `session` override guard — exactly as it is.

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/content_spec.rb`
Expected: PASS (14 examples)

- [ ] **Step 5: Run the full suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 189 examples. Watch `spec/requests/session_isolation_spec.rb` and `spec/requests/content_host_routing_spec.rb` — neither asserts on response bodies, so both should be unaffected.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/content_controller.rb spec/requests/content_spec.rb
git commit -m "Serve the McPublish banner above every hosted artifact"
```
