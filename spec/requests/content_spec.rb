require "rails_helper"

RSpec.describe "Content serving", type: :request do
  let(:user) { User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123") }
  let(:artifact) { Artifact.create!(user: user, storage_key: "artifacts/1", byte_size: 20, visibility: "public") }

  before do
    ArtifactStorage.client.stub_responses(:get_object, body: "<html>hello</html>")
    host! "content.mcpublish.ai"
  end

  it "serves the artifact's html" do
    get "/p/#{artifact.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<html>hello</html>")
    expect(response.content_type).to include("text/html")
  end

  it "sets no Set-Cookie header" do
    get "/p/#{artifact.slug}"
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "disables caching so updates via update_artifact are reflected immediately" do
    get "/p/#{artifact.slug}"
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "redirects to the view-authorization flow for an unknown slug" do
    get "/p/nosuchslug"
    expect(response).to redirect_to("https://mcpublish.ai/artifacts/nosuchslug/view")
  end

  it "sets no Set-Cookie header on the redirect path" do
    get "/p/nosuchslug"
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "returns 404 when the S3 object is missing despite a valid public record" do
    ArtifactStorage.client.stub_responses(:get_object, "NoSuchKey")
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "is not routable on the main app host" do
    host! "mcpublish.ai"
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "redirects to the view-authorization flow when the artifact is private and no token is given" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")

    get "/p/#{private_artifact.slug}"

    expect(response).to redirect_to("https://mcpublish.ai/artifacts/#{private_artifact.slug}/view")
  end

  it "serves a private artifact when a valid token is given" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")
    token = ContentAccessToken.generate(artifact: private_artifact, user: user)

    get "/p/#{private_artifact.slug}", params: { token: token }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<html>hello</html>")
  end

  it "redirects instead of serving when the token is for a different slug" do
    private_artifact = Artifact.create!(user: user, storage_key: "artifacts/2", byte_size: 5, visibility: "private")
    other_artifact = Artifact.create!(user: user, storage_key: "artifacts/3", byte_size: 5, visibility: "private")
    token = ContentAccessToken.generate(artifact: other_artifact, user: user)

    get "/p/#{private_artifact.slug}", params: { token: token }

    expect(response).to redirect_to("https://mcpublish.ai/artifacts/#{private_artifact.slug}/view")
  end
end
