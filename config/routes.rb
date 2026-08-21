Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "posts#index"

  content_host = Rails.application.config.x.content_host
  on_content_host = ->(req) { req.host.to_s.downcase.delete_suffix(".") == content_host }

  on_www = ->(req) { req.host.to_s.downcase.delete_suffix(".") == "www.mcpublish.ai" }

  constraints(on_www) do
    match "(*path)", to: redirect { |params, req| "https://mcpublish.ai#{req.fullpath}" }, via: :all
  end

  constraints(on_content_host) do
    get "/p/:slug", to: "content#show"
  end

  # Main-app-only routes: the content host must only ever be able to serve
  # artifact HTML, so these are excluded there even though nothing else routes
  # them on that host today.
  constraints(->(req) { !on_content_host.call(req) }) do
    root "pages#home"

    # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
    # Can be used by load balancers and uptime monitors to verify that the app is live.
    get "up" => "rails/health#show", as: :rails_health_check

    post "/mcp", to: "mcp#create"

    get "/signup", to: "users#new", as: :signup
    post "/signup", to: "users#create"
    get "/login", to: "sessions#new", as: :login
    post "/login", to: "sessions#create"
    delete "/logout", to: "sessions#destroy", as: :logout
    get "/account", to: "account#show", as: :account
    resources :api_keys, only: [ :index, :create, :destroy ]
    resources :organizations, only: [ :index, :new, :create, :show ] do
      member do
        post :invite
        delete "members/:membership_id", to: "organizations#remove_member", as: :remove_member
      end
    end
    get "/artifacts/:slug/view", to: "artifacts#view", as: :view_artifact
  end
end
