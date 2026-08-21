# Inherits ActionController::API directly (not ApplicationController).
# Session/cookie middleware is global to the Rack stack (it has to be, to
# support the web UI), so middleware absence alone no longer keeps this
# controller session-free. The `session` override below is the actual
# guard: it raises immediately if session is ever touched here, turning a
# future violation into a hard failure instead of a silent possibility.
#
# This controller never makes a permission decision. It only knows two
# things: is this artifact public (serve it), or is there a valid,
# slug-matching signed token (serve it) — anything else redirects to the
# main app's view-authorization endpoint, which does have a session and
# makes the actual call. That includes a nonexistent slug: routing both
# "doesn't exist" and "exists but forbidden" through the same endpoint is
# what gives them an identical response.
class ContentController < ActionController::API
  def show
    artifact = Artifact.find_by(slug: params[:slug])

    if artifact&.visibility == "public"
      serve(artifact)
      return
    end

    payload = artifact && ContentAccessToken.verify(params[:token], slug: params[:slug])
    if payload && payload[:artifact_id] == artifact.id
      serve(artifact)
      return
    end

    redirect_to "https://#{Rails.application.config.x.main_host}/artifacts/#{params[:slug]}/view",
      allow_other_host: true
  end

  private

  def serve(artifact)
    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: html, content_type: "text/html"
  end

  def session
    raise "ContentController must never access the session"
  end
end
