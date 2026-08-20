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
    return nil unless header&.match?(/\ABearer /i)

    header.sub(/\ABearer /i, "")
  end

  def current_api_key
    @current_api_key
  end

  # Relies on the including controller defining a private `payload` method
  # (parsed JSON body) — true of every controller that currently includes
  # this concern (McpController). A future includer without one would need
  # to add it or override this method.
  def render_unauthorized
    render json: {
      jsonrpc: "2.0",
      id: payload["id"],
      error: { code: -32001, message: "Unauthorized: missing or invalid API key" }
    }, status: :unauthorized
  end
end
