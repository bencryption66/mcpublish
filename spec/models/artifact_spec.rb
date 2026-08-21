require "rails_helper"

RSpec.describe Artifact, type: :model do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }

  it "auto-assigns a slug on create" do
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to match(/\A[a-zA-Z0-9]{8}\z/)
  end

  it "does not overwrite an explicitly-set slug" do
    artifact = Artifact.create!(user: user, slug: "custom01", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.slug).to eq("custom01")
  end

  it "builds a content URL from the slug" do
    artifact = Artifact.create!(user: user, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://content.mcpublish.ai/p/abcd1234")
  end

  it "builds the content URL from the configured content host, not a hardcoded constant" do
    original_content_host = Rails.application.config.x.content_host
    Rails.application.config.x.content_host = "artifacts.example.com"

    artifact = Artifact.create!(user: user, slug: "abcd1234", storage_key: "artifacts/1", byte_size: 10)
    expect(artifact.url).to eq("https://artifacts.example.com/p/abcd1234")
  ensure
    Rails.application.config.x.content_host = original_content_host
  end

  it "requires a positive byte_size" do
    artifact = Artifact.new(user: user, storage_key: "artifacts/1", byte_size: 0)
    expect(artifact).not_to be_valid
  end

  it "is accessible via user#artifacts" do
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10)
    expect(user.artifacts).to include(artifact)
  end
end
