class WebController < ActionController::Base
  protect_from_forgery with: :exception
  include Authenticatable

  # Rails' automatic layout lookup matches the controller name
  # (e.g. layouts/account, layouts/sessions) with a fallback to
  # layouts/application — neither exists, so without this the
  # layouts/web.html.erb template below would silently never render.
  layout "web"
end
