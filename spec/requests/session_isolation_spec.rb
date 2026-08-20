require "rails_helper"

RSpec.describe "Session middleware does not leak into API-only hosts", type: :request do
  it "does not set a cookie on POST /mcp" do
    token = ApiKey.issue!(label: "Alice").last

    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }

    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "does not set a cookie on GET content.mcpublish.ai/p/:slug" do
    api_key = ApiKey.issue!(label: "Alice").first
    artifact = Artifact.create!(api_key: api_key, storage_key: "artifacts/1", byte_size: 5)
    ArtifactStorage.client.stub_responses(:get_object, body: "<html>hi</html>")

    host! "content.mcpublish.ai"
    get "/p/#{artifact.slug}"

    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "raises if McpController's session is ever accessed" do
    expect { McpController.new.send(:session) }.to raise_error(/must never access the session/)
  end

  it "raises if ContentController's session is ever accessed" do
    expect { ContentController.new.send(:session) }.to raise_error(/must never access the session/)
  end
end
