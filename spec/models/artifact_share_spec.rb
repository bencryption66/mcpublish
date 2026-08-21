require "rails_helper"

RSpec.describe ArtifactShare do
  let(:user) { User.create!(email: "owner@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5) }

  it "requires a valid email" do
    share = ArtifactShare.new(artifact: artifact, email: "not-an-email")
    expect(share).not_to be_valid
  end

  it "normalizes email to lowercase" do
    share = ArtifactShare.create!(artifact: artifact, email: "Invitee@Example.com")
    expect(share.email).to eq("invitee@example.com")
  end

  it "is valid without a user (pending claim)" do
    share = ArtifactShare.new(artifact: artifact, email: "invitee@example.com")
    expect(share).to be_valid
  end

  it "prevents duplicate emails on the same artifact" do
    ArtifactShare.create!(artifact: artifact, email: "invitee@example.com")
    dupe = ArtifactShare.new(artifact: artifact, email: "invitee@example.com")

    expect(dupe).not_to be_valid
  end

  it "is destroyed when its artifact is destroyed" do
    share = ArtifactShare.create!(artifact: artifact, email: "invitee@example.com")
    artifact.destroy!

    expect(ArtifactShare.exists?(share.id)).to eq(false)
  end
end
