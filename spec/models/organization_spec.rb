require "rails_helper"

RSpec.describe Organization, type: :model do
  it "requires a name" do
    org = Organization.new(slug: "acme")
    expect(org).not_to be_valid
  end

  it "requires a unique slug" do
    Organization.create!(name: "Acme", slug: "acme")
    dupe = Organization.new(name: "Acme Two", slug: "acme")

    expect(dupe).not_to be_valid
  end

  it "rejects a slug with invalid characters" do
    org = Organization.new(name: "Acme", slug: "Not Valid!")
    expect(org).not_to be_valid
  end

  it "accepts a lowercase, hyphenated slug" do
    org = Organization.new(name: "Acme", slug: "acme-co")
    expect(org).to be_valid
  end

  it "is accessible via organization#artifacts" do
    org = Organization.create!(name: "Acme", slug: "acme")
    user = User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123")
    artifact = Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 10, visibility: "organisation", organization: org)

    expect(org.artifacts).to include(artifact)
  end
end
