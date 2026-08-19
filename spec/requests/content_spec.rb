require "rails_helper"

RSpec.describe "Content serving", type: :request do
  let(:api_key) { ApiKey.issue!(label: "Alice").first }
  let(:artifact) { Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 20) }

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

  it "returns 404 for an unknown slug" do
    get "/p/nosuchslug"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the S3 object is missing despite a valid record" do
    ArtifactStorage.client.stub_responses(:get_object, "NoSuchKey")
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it "is not routable on the main app host" do
    host! "mcpublish.ai"
    get "/p/#{artifact.slug}"
    expect(response).to have_http_status(:not_found)
  end
end
