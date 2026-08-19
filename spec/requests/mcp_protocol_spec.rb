require "rails_helper"

RSpec.describe "MCP protocol", type: :request do
  let!(:api_key) { ApiKey.issue!(label: "Alice") }
  let(:token) { api_key.last }

  def post_mcp(body, token: nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: body.to_json, headers: headers
  end

  it "rejects requests with no Authorization header" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" })
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with an invalid token" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: "mcpub_bogus")
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects requests with a revoked key's token" do
    api_key.first.update!(revoked_at: Time.current)
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "handles initialize for a valid key" do
    post_mcp({ jsonrpc: "2.0", id: 1, method: "initialize" }, token: token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["result"]["protocolVersion"]).to be_present
    expect(body["result"]["capabilities"]).to eq({ "tools" => {} })
  end

  it "lists all four tools" do
    post_mcp({ jsonrpc: "2.0", id: 2, method: "tools/list" }, token: token)

    expect(response).to have_http_status(:ok)
    tool_names = JSON.parse(response.body)["result"]["tools"].map { |t| t["name"] }
    expect(tool_names).to contain_exactly(
      "publish_artifact", "update_artifact", "list_artifacts", "delete_artifact"
    )
  end

  it "returns a JSON-RPC error for an unknown method" do
    post_mcp({ jsonrpc: "2.0", id: 3, method: "nonexistent" }, token: token)

    body = JSON.parse(response.body)
    expect(body["error"]["code"]).to eq(-32601)
  end
end
