Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "posts#index"

  content_host = Rails.application.config.x.content_host.to_s.downcase.delete_suffix(".")
  on_content_host = ->(req) { req.host.to_s.downcase.delete_suffix(".") == content_host }

  constraints(on_content_host) do
    get "/p/:slug", to: "content#show"
  end

  # Main-app-only routes: the content host must only ever be able to serve
  # artifact HTML, so these are excluded there even though nothing else routes
  # them on that host today.
  constraints(->(req) { !on_content_host.call(req) }) do
    # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
    # Can be used by load balancers and uptime monitors to verify that the app is live.
    get "up" => "rails/health#show", as: :rails_health_check

    post "/mcp", to: "mcp#create"
  end
end
