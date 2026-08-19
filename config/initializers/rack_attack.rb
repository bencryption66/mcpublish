class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  throttle("mcp/publish-updates", limit: 30, period: 60) do |request|
    next unless request.path == "/mcp" && request.post?

    body = request.body.read
    request.body.rewind

    payload = begin
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
    next unless payload
    next unless payload["method"] == "tools/call"
    next unless %w[publish_artifact update_artifact].include?(payload.dig("params", "name"))

    request.get_header("HTTP_AUTHORIZATION")
  end
end

Rails.application.config.middleware.use Rack::Attack
