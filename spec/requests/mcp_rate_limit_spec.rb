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
    # Rack::Attack buckets requests by Time.now.to_i / period, so an
    # unfrozen clock could straddle a window boundary mid-test and reset
    # the count. Freezing time keeps all 31 calls in the same window.
    freeze_time do
      30.times { call_tool("publish_artifact", { html: "<html>x</html>" }) }
      expect(response).not_to have_http_status(:too_many_requests)

      call_tool("publish_artifact", { html: "<html>x</html>" })
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "does not throttle list_artifacts even past 30 calls" do
    freeze_time do
      35.times { call_tool("list_artifacts", {}) }
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  it "does not dispatch based on query-string params, only the parsed JSON body" do
    post "/mcp?method=tools/call&params[name]=publish_artifact&params[arguments][html]=<html>x</html>",
      params: "{}",
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }

    json = JSON.parse(response.body)

    expect(json["error"]).to be_present
    expect(json["error"]["message"]).to match(/Method not found/)
    expect(Artifact.count).to eq(0)
  end
end
