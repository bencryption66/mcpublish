class ApiKeysController < WebController
  before_action :require_login!

  def index
    @api_keys = current_user.api_keys.order(created_at: :desc)
  end

  def create
    _api_key, raw_token = ApiKey.issue!(label: params[:label], user: current_user)
    flash[:new_api_key] = raw_token
    redirect_to api_keys_path, notice: "API key created — copy it below, it will not be shown again."
  end

  def destroy
    api_key = current_user.api_keys.find(params[:id])
    api_key.update!(revoked_at: Time.current)
    redirect_to api_keys_path, notice: "API key revoked"
  end
end
