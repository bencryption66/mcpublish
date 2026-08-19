require "rails_helper"

RSpec.describe Artifact, type: :model do
  let(:api_key) { ApiKey.issue!(label: "Alice").first }

  it "auto-assigns a slug on create" do
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to match(/\A[a-zA-Z0-9]{8}\z/)
  end

  it "does not overwrite an explicitly-set slug" do
    artifact = Artifact.create!(api_key: api_key, slug: "custom01", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to eq("custom01")
  end

  it "builds a content URL from the slug" do
    artifact = Artifact.create!(api_key: api_key, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://content.mcpublish.ai/p/abcd1234")
  end

  it "requires a positive byte_size" do
    artifact = Artifact.new(api_key: api_key, storage_key: "artifacts/1", byte_size: 0)
    expect(artifact).not_to be_valid
  end

  it "is accessible via api_key#artifacts" do
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 10)
    expect(api_key.artifacts).to include(artifact)
  end
end
