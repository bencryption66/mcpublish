require "rails_helper"

RSpec.describe "Artifact view authorization", type: :request do
  let(:owner) { User.create!(email: "owner@example.com", password: "password123", password_confirmation: "password123") }
  let(:stranger) { User.create!(email: "stranger@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "redirects to login when signed out, preserving the return path" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to redirect_to("/login")
  end

  it "redirects the owner back to the login-preserved path after signing in" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")

    get "/artifacts/#{artifact.slug}/view"
    post "/login", params: { email: owner.email, password: "password123" }

    expect(response).to redirect_to("/artifacts/#{artifact.slug}/view")
  end

  it "grants the owner a signed content-access token and redirects to the content host" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(owner)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
    location = URI.parse(response.headers["Location"])
    expect(location.host).to eq("content.mcpublish.ai")
    expect(location.path).to eq("/p/#{artifact.slug}")
    expect(Rack::Utils.parse_query(location.query)).to have_key("token")
  end

  it "returns the generic not-found for a stranger on a private artifact" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "returns the identical response for a nonexistent slug and a forbidden one" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "private")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"
    forbidden_body = response.body

    get "/artifacts/nosuchslug/view"
    missing_body = response.body

    expect(forbidden_body).to eq(missing_body)
    expect(response).to have_http_status(:not_found)
  end

  it "grants access to an organisation member" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    member = User.create!(email: "member@example.com", password: "password123", password_confirmation: "password123")
    OrganizationMembership.create!(user: member, organization: org, role: "member")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(member)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end

  it "denies a non-member on an organisation artifact" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "revokes access dynamically when a member is removed from the organisation" do
    org = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: owner, organization: org, role: "admin")
    membership = OrganizationMembership.create!(user: stranger, organization: org, role: "member")
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "organisation", organization: org)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"
    expect(response).to have_http_status(:found)

    membership.destroy!

    get "/artifacts/#{artifact.slug}/view"
    expect(response).to have_http_status(:not_found)
  end

  it "grants access to a shared user" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "shared")
    ArtifactShare.create!(artifact: artifact, email: stranger.email, user: stranger)
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end

  it "denies a user not on the share list" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "shared")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:not_found)
  end

  it "grants access to a public artifact reached directly" do
    artifact = Artifact.create!(user: owner, storage_key: "artifacts/1", byte_size: 5, visibility: "public")
    sign_in_as(stranger)

    get "/artifacts/#{artifact.slug}/view"

    expect(response).to have_http_status(:found)
  end
end
