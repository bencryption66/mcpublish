Rails.application.config.x.content_host = ENV.fetch("CONTENT_HOST", "content.mcpublish.ai")
Rails.application.config.x.content_subdomain = Rails.application.config.x.content_host.split(".").first
