require "rails_helper"
require "benchmark"

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

      expect(result).to include(%(href="https://mcpublish.ai" target="_blank" rel="noopener noreferrer"))
      expect(result).to include(%(href="https://mcpublish.ai/signup" target="_blank" rel="noopener noreferrer"))
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

    it "reserves space for the fixed banner" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include("padding-top:44px !important")
      expect(result).to include("position:fixed !important")
      expect(result).to include("z-index:2147483647 !important")
      expect(result).to include("@media (max-width:640px)")
    end

    it "scopes every css rule to the banner or the html space reservation" do
      css = described_class.inject("<html><body></body></html>")[%r{<style[^>]*>(.*?)</style>}m, 1]
      selectors = css.scan(/(?:\A|[{}])\s*([^{}@]+?)\s*\{/).flatten

      expect(selectors).not_to be_empty
      selectors.flat_map { |group| group.split(",") }.map(&:strip).each do |selector|
        expect(selector.start_with?("#mcpublish-banner") || selector == "html").to be(true),
          "unscoped selector in banner CSS: #{selector.inspect}"
      end
    end

    it "hides the banner and releases the reserved space when printing" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include("@media print{#mcpublish-banner{display:none !important}html{padding-top:0 !important}}")
    end

    it "offsets scroll anchors so in-page links do not land under the banner" do
      result = described_class.inject("<html><body></body></html>")

      expect(result).to include("scroll-padding-top:44px !important")
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

    it "does not mistake a hyphenated custom element for the body tag" do
      result = described_class.inject("<html><body-scroll-lock></body-scroll-lock><body><p>Real</p></body></html>")

      expect(result.index("mcpublish-banner")).to be > result.index("</body-scroll-lock>")
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Real</p>")
    end

    it "skips a body tag inside an HTML comment and uses the real one" do
      result = described_class.inject("<!-- <body> --><html><body><p>Real</p></body></html>")

      expect(result.index("mcpublish-banner")).to be > result.index("-->")
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Real</p>")
    end

    it "skips a body tag inside a script string literal and uses the real one" do
      html = %(<html><head><script>const t='<html><body>x</body></html>';</script></head><body><p>Real</p></body></html>)

      result = described_class.inject(html)

      expect(result).to include(%(const t='<html><body>x</body></html>';))
      expect(result.index("mcpublish-banner")).to be > result.index("</script>")
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Real</p>")
    end

    it "stays linear on an artifact packed with body tags inside a script" do
      payload = "<html><head><script>" + ("<body>" * 50_000) + "</script></head><body><p>Real</p></body></html>"

      elapsed = Benchmark.realtime { described_class.inject(payload) }

      expect(elapsed).to be < 1.0
    end

    it "is not fooled by a </script> appearing inside a comment" do
      html = %(<!-- </script> --><html><head><script>var s="<body>";</script></head><body><p>Real</p></body></html>)

      result = described_class.inject(html)

      expect(result).to include(%(var s="<body>";))
      expect(result.index("mcpublish-banner")).to be > result.rindex("</script>")
      expect(result.index("mcpublish-banner")).to be < result.index("<p>Real</p>")
    end

    it "falls back to the doctype branch when a script is never closed" do
      result = described_class.inject("<!DOCTYPE html><html><script>var s='<body>';")

      expect(result).to start_with("<!DOCTYPE html>")
      expect(result.index("mcpublish-banner")).to be < result.index("<script>")
    end
  end
end
