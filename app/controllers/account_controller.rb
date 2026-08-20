class AccountController < WebController
  before_action :require_login!

  def show
  end
end
