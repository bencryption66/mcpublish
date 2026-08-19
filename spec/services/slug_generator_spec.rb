require "rails_helper"

RSpec.describe SlugGenerator do
  describe ".generate_unique" do
    it "returns an 8-character alphanumeric string" do
      slug = SlugGenerator.generate_unique
      expect(slug).to match(/\A[a-zA-Z0-9]{8}\z/)
    end

    it "does not return a slug already used by an existing artifact" do
      api_key, = ApiKey.issue!(label: "Alice")
      taken_slug = SlugGenerator.generate_unique
      Artifact.create!(api_key: api_key, slug: taken_slug, storage_key: "artifacts/1", byte_size: 10)

      allow(SlugGenerator).to receive(:candidate).and_return(taken_slug, "freshone1")

      expect(SlugGenerator.generate_unique).to eq("freshone1")
    end
  end

  describe ".candidate" do
    it "draws characters from a cryptographically secure source, not Array#sample" do
      expect(SecureRandom).to receive(:random_number).at_least(:once).and_call_original

      SlugGenerator.candidate
    end
  end
end
