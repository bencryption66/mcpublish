# Inherits ActionController::API directly (not ApplicationController).
# Session/cookie middleware is global to the Rack stack (it has to be, to
# support the web UI), so middleware absence alone no longer keeps this
# controller session-free. The `session` override below is the actual
# guard: it raises immediately if session is ever touched here, turning a
# future violation into a hard failure instead of a silent possibility.
class ContentController < ActionController::API
  def show
    artifact = Artifact.find_by(slug: params[:slug])
    return head :not_found unless artifact

    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: html, content_type: "text/html"
  end

  private

  def session
    raise "ContentController must never access the session"
  end
end
