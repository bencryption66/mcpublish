require "rails_helper"

RSpec.describe ContentAccessToken do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 5, slug: "abcd1234") }

  it "generates a token that verifies for the same slug" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    payload = ContentAccessToken.verify(token, slug: artifact.slug)

    expect(payload[:artifact_id]).to eq(artifact.id)
    expect(payload[:user_id]).to eq(user.id)
  end

  it "rejects a token verified against a different slug" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    expect(ContentAccessToken.verify(token, slug: "different-slug")).to be_nil
  end

  it "rejects a tampered token" do
    token = ContentAccessToken.generate(artifact: artifact, user: user)
    expect(ContentAccessToken.verify(token + "x", slug: artifact.slug)).to be_nil
  end

  it "rejects a blank token" do
    expect(ContentAccessToken.verify(nil, slug: artifact.slug)).to be_nil
    expect(ContentAccessToken.verify("", slug: artifact.slug)).to be_nil
  end

  it "rejects an expired token" do
    token = nil
    travel_to 2.hours.ago do
      token = ContentAccessToken.generate(artifact: artifact, user: user)
    end

    expect(ContentAccessToken.verify(token, slug: artifact.slug)).to be_nil
  end
end
