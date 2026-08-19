require "rails_helper"

RSpec.describe ApiKey, type: :model do
  describe ".issue!" do
    it "creates an api key and returns it with a raw token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(api_key).to be_persisted
      expect(api_key.label).to eq("Alice")
      expect(raw_token).to start_with("mcpub_")
    end

    it "does not store the raw token anywhere retrievable" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(api_key.token_digest).not_to eq(raw_token)
    end
  end

  describe ".authenticate" do
    it "returns the matching api key for a valid raw token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")

      expect(ApiKey.authenticate(raw_token)).to eq(api_key)
    end

    it "returns nil for an unknown token" do
      expect(ApiKey.authenticate("mcpub_does_not_exist")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(ApiKey.authenticate(nil)).to be_nil
      expect(ApiKey.authenticate("")).to be_nil
    end

    it "returns nil for a revoked key's token" do
      api_key, raw_token = ApiKey.issue!(label: "Alice")
      api_key.update!(revoked_at: Time.current)

      expect(ApiKey.authenticate(raw_token)).to be_nil
    end
  end

  describe "#revoked?" do
    it "is false when revoked_at is nil" do
      api_key, = ApiKey.issue!(label: "Alice")
      expect(api_key.revoked?).to eq(false)
    end

    it "is true when revoked_at is set" do
      api_key, = ApiKey.issue!(label: "Alice")
      api_key.update!(revoked_at: Time.current)
      expect(api_key.revoked?).to eq(true)
    end
  end
end
