module Authenticatable
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  def require_login!
    redirect_to login_path, alert: "Please log in first" unless current_user
  end
end
