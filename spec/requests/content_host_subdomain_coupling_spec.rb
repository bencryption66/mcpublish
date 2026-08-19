require "rails_helper"

RSpec.describe "Content host / route host coupling", type: :request do
  it "routes /p/:slug and excludes /mcp based on req.host compared directly to content_host" do
    original_host = Rails.application.config.x.content_host

    begin
      # A realistic staging-style CONTENT_HOST: four labels. Under the old
      # naive `content_host.split(".").first` approach, Rails'
      # TLD-aware req.subdomain for this host would be "content.staging",
      # not "content" -- so the old subdomain-based constraints would have
      # silently failed to match here, leaving /mcp reachable on the
      # content-serving host. Comparing req.host directly sidesteps that
      # entirely.
      Rails.application.config.x.content_host = "content.staging.mcpublish.ai"
      Rails.application.reload_routes!

      api_key = ApiKey.issue!(label: "Bob").first
      artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 20)
      ArtifactStorage.client.stub_responses(:get_object, body: "<html>hi</html>")

      # The content route now follows the new content_host...
      host! "content.staging.mcpublish.ai"
      get "/p/#{artifact.slug}"
      expect(response).to have_http_status(:ok)

      # ...and /mcp is excluded there.
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:not_found)

      # The old default content host no longer serves artifacts...
      host! "content.mcpublish.ai"
      get "/p/#{artifact.slug}"
      expect(response).to have_http_status(:not_found)

      # ...and is no longer excluded from main-app routes (proving the
      # isolation gap moves with the config instead of silently reopening
      # on the old host).
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized) # routed, but rejected for lacking a token
    ensure
      Rails.application.config.x.content_host = original_host
      Rails.application.reload_routes!
    end
  end
end
