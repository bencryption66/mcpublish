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
end
