require "rails_helper"

RSpec.describe "Shared web layout", type: :request do
  it "renders the nav with the logo lockup and beta pill on public pages" do
    get "/login"

    expect(response.body).to include("site-nav")
    expect(response.body).to include("logo-lockup")
    expect(response.body).to include("beta-pill")
    expect(response.body).to include("/assets/site.css?v=1")
    expect(response.body).to include("/icon.svg")
  end

  it "shows Log in and Sign up when signed out" do
    get "/login"

    expect(response.body).to include("Sign up")
    expect(response.body).to include("nav-links")
  end

  it "shows Account and Log out when signed in" do
    User.create!(email: "nav@example.com", password: "password123", password_confirmation: "password123")
    post "/login", params: { email: "nav@example.com", password: "password123" }
    get "/account"

    expect(response.body).to include(">Account</a>")
    expect(response.body).to include("Log out")
  end

  it "renders the footer with the beta note" do
    get "/login"

    expect(response.body).to include("site-footer")
    expect(response.body).to include("things may occasionally wobble")
  end
end
