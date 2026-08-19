require "rails_helper"

RSpec.describe "MCP rate limiting", type: :request do
  let(:token) { ApiKey.issue!(label: "Alice").last }

  before { Rack::Attack.cache.store.clear }

  def call_tool(name, arguments)
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  it "throttles publish_artifact calls after 30 in a minute" do
    30.times { call_tool("publish_artifact", { html: "<html>x</html>" }) }
    expect(response).not_to have_http_status(:too_many_requests)

    call_tool("publish_artifact", { html: "<html>x</html>" })
    expect(response).to have_http_status(:too_many_requests)
  end

  it "does not throttle list_artifacts even past 30 calls" do
    35.times { call_tool("list_artifacts", {}) }
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
