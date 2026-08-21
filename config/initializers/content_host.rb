Rails.application.config.x.content_host =
  ENV.fetch("CONTENT_HOST", "content.mcpublish.ai").to_s.strip.downcase.delete_suffix(".")

Rails.application.config.x.main_host =
  ENV.fetch("MAIN_HOST", "mcpublish.ai").to_s.strip.downcase.delete_suffix(".")
