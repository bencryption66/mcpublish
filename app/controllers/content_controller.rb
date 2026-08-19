# Inherits ActionController::API directly (not ApplicationController) so this
# controller can never pick up session/cookie middleware, even if
# ApplicationController gains it later for the dashboard (sub-project 4).
class ContentController < ActionController::API
  def show
    artifact = Artifact.find_by(slug: params[:slug])
    return head :not_found unless artifact

    html = ArtifactStorage.get(storage_key: artifact.storage_key)
    return head :not_found unless html

    response.headers["Cache-Control"] = "no-store"
    render plain: html, content_type: "text/html"
  end
end
