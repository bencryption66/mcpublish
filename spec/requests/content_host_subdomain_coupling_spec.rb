require "rails_helper"

RSpec.describe "Content host / route subdomain coupling", type: :request do
  it "derives content_subdomain from content_host so the two can never drift apart" do
    expect(Rails.application.config.x.content_subdomain)
      .to eq(Rails.application.config.x.content_host.split(".").first)
  end

  it "moves both the content route and the main-app exclusion when content_subdomain changes" do
    original_subdomain = Rails.application.config.x.content_subdomain

    begin
      Rails.application.config.x.content_subdomain = "artifacts"
      Rails.application.reload_routes!

      api_key = ApiKey.issue!(label: "Bob").first
      artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 20)
      ArtifactStorage.client.stub_responses(:get_object, body: "<html>hi</html>")

      # The content route now follows the new subdomain...
      host! "artifacts.mcpublish.ai"
      get "/p/#{artifact.slug}"
      expect(response).to have_http_status(:ok)

      # ...and /mcp is excluded there instead of on the old "content" literal.
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:not_found)

      # The old "content" subdomain no longer serves artifacts...
      host! "content.mcpublish.ai"
      get "/p/#{artifact.slug}"
      expect(response).to have_http_status(:not_found)

      # ...and is no longer excluded from main-app routes (proving the isolation
      # gap moves with the config instead of silently reopening on "content").
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized) # routed, but rejected for lacking a token
    ensure
      Rails.application.config.x.content_subdomain = original_subdomain
      Rails.application.reload_routes!
    end
  end
end
