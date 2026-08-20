require "rails_helper"

RSpec.describe "Signup", type: :request do
  it "creates a user and signs them in" do
    post "/signup", params: { user: { email: "new@example.com", password: "password123", password_confirmation: "password123" } }

    expect(response).to redirect_to("/account")
    follow_redirect!
    expect(response.body).to include("new@example.com")
  end

  it "re-renders the form with errors on invalid input" do
    post "/signup", params: { user: { email: "not-an-email", password: "short", password_confirmation: "short" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(User.count).to eq(0)
  end

  it "claims any pending organization invites matching the new user's email" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationInvite.create!(organization: organization, email: "invited@example.com")

    post "/signup", params: { user: { email: "invited@example.com", password: "password123", password_confirmation: "password123" } }

    user = User.find_by!(email: "invited@example.com")
    expect(user.organizations).to include(organization)
    expect(OrganizationInvite.exists?(organization: organization, email: "invited@example.com")).to eq(false)
  end
end
