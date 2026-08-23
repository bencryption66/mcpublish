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
