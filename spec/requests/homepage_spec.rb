require "rails_helper"

RSpec.describe "Homepage", type: :request do
  it "renders the verb hero on the main host" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Just <span class=\"hero-accent\">McPublish</span> it.")
    expect(response.body).to include("Get started free")
    expect(response.body).to include("Things people McPublish")
  end

  it "sets the homepage title" do
    get "/"
    expect(response.body).to include("<title>McPublish.ai — Just McPublish it</title>")
  end

  it "is not routable on the content host" do
    host! "content.mcpublish.ai"
    get "/"
    expect(response).to have_http_status(:not_found)
  end

  it "shows Account in the nav when signed in" do
    User.create!(email: "home@example.com", password: "password123", password_confirmation: "password123")
    post "/login", params: { email: "home@example.com", password: "password123" }
    get "/"

    expect(response.body).to include(">Account</a>")
  end
end
