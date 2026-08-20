require "rails_helper"

RSpec.describe "Web login/signup rate limiting", type: :request do
  before { Rack::Attack.cache.store.clear }

  it "throttles POST /login by IP after 10 attempts in a minute" do
    freeze_time do
      10.times { |i| post "/login", params: { email: "nobody#{i}@example.com", password: "wrong" } }
      expect(response).not_to have_http_status(:too_many_requests)

      post "/login", params: { email: "overflow@example.com", password: "wrong" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "throttles POST /signup by IP after 10 attempts in a minute" do
    freeze_time do
      10.times { |i| post "/signup", params: { user: { email: "user#{i}@example.com", password: "password123", password_confirmation: "password123" } } }
      expect(response).not_to have_http_status(:too_many_requests)

      post "/signup", params: { user: { email: "overflow@example.com", password: "password123", password_confirmation: "password123" } }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "throttles POST /login by submitted email after 5 attempts in a minute" do
    freeze_time do
      5.times { post "/login", params: { email: "target@example.com", password: "wrong" } }
      expect(response).not_to have_http_status(:too_many_requests)

      post "/login", params: { email: "target@example.com", password: "wrong" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
