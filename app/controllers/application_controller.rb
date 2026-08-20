class ApplicationController < ActionController::API
  private

  # McpController must never touch the session — see
  # docs/superpowers/specs/2026-08-19-core-hosting-engine-design.md's
  # isolation discussion. ActionController::Metal delegates `session` to
  # the request regardless of controller type, so this needs an explicit
  # guard rather than relying on module absence alone.
  def session
    raise "ApplicationController (and McpController) must never access the session"
  end
end
