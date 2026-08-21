class ArtifactsController < WebController
  def view
    artifact = Artifact.find_by(slug: params[:slug])

    unless current_user
      session[:return_to] = request.fullpath
      redirect_to login_path, alert: "Please log in first"
      return
    end

    if artifact.nil? || !permitted?(artifact)
      render_not_found
      return
    end

    token = ContentAccessToken.generate(artifact: artifact, user: current_user)
    redirect_to "https://#{Rails.application.config.x.content_host}/p/#{artifact.slug}?token=#{CGI.escape(token)}",
      allow_other_host: true
  end

  private

  def permitted?(artifact)
    return true if artifact.visibility == "public"
    return true if artifact.user_id == current_user.id
    return true if artifact.visibility == "organisation" && current_user.organizations.exists?(id: artifact.organization_id)
    return true if artifact.visibility == "shared" && artifact.artifact_shares.exists?(user_id: current_user.id)

    false
  end

  def render_not_found
    render plain: "Not found", status: :not_found
  end
end
