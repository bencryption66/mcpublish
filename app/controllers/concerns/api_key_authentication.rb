module ApiKeyAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
  end

  private

  def authenticate_api_key!
    @current_api_key = ApiKey.authenticate(bearer_token)
    render_unauthorized unless @current_api_key
  end

  def bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.delete_prefix("Bearer ")
  end

  def current_api_key
    @current_api_key
  end

  def render_unauthorized
    render json: {
      jsonrpc: "2.0",
      id: params[:id],
      error: { code: -32001, message: "Unauthorized: missing or invalid API key" }
    }, status: :unauthorized
  end
end
