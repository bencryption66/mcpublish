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

    expect(response.body).to include(%(<a href="/signup" class="btn btn-primary btn-sm">))
    expect(response.body).not_to include(">Account</a>")
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

  it "renders the signup page as an auth card with the verb heading" do
    get "/signup"

    expect(response.body).to include("Start McPublishing")
    expect(response.body).to include("auth-card")
  end

  it "renders the login page as an auth card" do
    get "/login"

    expect(response.body).to include("auth-card")
  end

  it "serves the stylesheet as a static file" do
    get "/assets/site.css"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("--persimmon")
  end

  it "serves the icon as a static file" do
    get "/icon.svg"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("#e8643c")
  end

  it "redirects www to the apex domain, preserving the path" do
    host! "www.mcpublish.ai"
    get "/login"

    expect(response).to redirect_to("https://mcpublish.ai/login")
  end

  it "renders alert flashes with the flash-alert class" do
    get "/account"
    follow_redirect!

    expect(response.body).to include("flash flash-alert")
  end
end
