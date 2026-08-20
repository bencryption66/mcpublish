require "rails_helper"

RSpec.describe "Login and logout", type: :request do
  let!(:user) { User.create!(email: "dana@example.com", password: "password123", password_confirmation: "password123") }

  it "logs in with correct credentials and reaches the account page" do
    post "/login", params: { email: "dana@example.com", password: "password123" }

    expect(response).to redirect_to("/account")
    follow_redirect!
    expect(response.body).to include("dana@example.com")
  end

  it "rejects incorrect credentials" do
    post "/login", params: { email: "dana@example.com", password: "wrong" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires login to view the account page" do
    get "/account"
    expect(response).to redirect_to("/login")
  end

  it "logs out and revokes access to the account page" do
    post "/login", params: { email: "dana@example.com", password: "password123" }

    delete "/logout"
    expect(response).to redirect_to("/login")

    get "/account"
    expect(response).to redirect_to("/login")
  end

  it "renders the login page layout without error (regression: ActionDispatch::Flash must be loaded)" do
    get "/login"
    expect(response).to have_http_status(:ok)
  end

  it "logs out via a browser-style method-override POST" do
    user = User.create!(email: "browser-test@example.com", password: "password123", password_confirmation: "password123")
    post "/login", params: { email: user.email, password: "password123" }

    post "/logout", params: { _method: "delete" }

    expect(response).to redirect_to("/login")
  end
end
