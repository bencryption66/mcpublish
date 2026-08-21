require "rails_helper"

RSpec.describe "API key management", type: :request do
  let(:user) { User.create!(email: "frank@example.com", password: "password123", password_confirmation: "password123") }
  let(:other_user) { User.create!(email: "gina@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "requires login" do
    get "/api_keys"
    expect(response).to redirect_to("/login")
  end

  it "generates a new key for the signed-in user" do
    sign_in_as(user)

    expect {
      post "/api_keys", params: { label: "My laptop" }
    }.to change { user.api_keys.count }.by(1)

    expect(response).to redirect_to("/api_keys")
    expect(user.api_keys.last.label).to eq("My laptop")
  end

  it "shows the raw token and a ready-to-paste MCP command once after creation" do
    sign_in_as(user)

    post "/api_keys", params: { label: "My laptop" }
    follow_redirect!

    expect(response.body).to match(/mcpub_[0-9a-f]{64}/)
    expect(response.body).to include("claude mcp add --transport http mcpublish https://mcpublish.ai/mcp")
    expect(response.body).to match(%r{Authorization: Bearer mcpub_[0-9a-f]{64}})

    get "/api_keys"
    expect(response.body).not_to match(/mcpub_[0-9a-f]{64}/)
  end

  it "always shows the MCP connect snippet with a placeholder key" do
    sign_in_as(user)
    get "/api_keys"

    expect(response.body).to include("claude mcp add --transport http mcpublish https://mcpublish.ai/mcp")
    expect(response.body).to include("YOUR_API_KEY")
  end

  it "does not render the raw token as a flash bar" do
    sign_in_as(user)

    post "/api_keys", params: { label: "My laptop" }
    follow_redirect!

    expect(response.body).not_to match(/flash flash-notice[^<]*mcpub_/)
  end

  it "revokes only the current user's own key" do
    sign_in_as(user)
    api_key, = ApiKey.issue!(label: "Mine", user: user)

    delete "/api_keys/#{api_key.id}"

    expect(api_key.reload.revoked?).to eq(true)
  end

  it "cannot revoke another user's key" do
    sign_in_as(user)
    other_key, = ApiKey.issue!(label: "Not yours", user: other_user)

    delete "/api_keys/#{other_key.id}"

    expect(response).to have_http_status(:not_found)
    expect(other_key.reload.revoked?).to eq(false)
  end
end
