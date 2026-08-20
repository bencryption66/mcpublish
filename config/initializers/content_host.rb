Rails.application.config.x.content_host =
  ENV.fetch("CONTENT_HOST", "content.mcpublish.ai").to_s.strip.downcase.delete_suffix(".")
