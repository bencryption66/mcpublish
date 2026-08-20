class OrganizationsController < WebController
  before_action :require_login!

  def index
    @organizations = current_user.organizations
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(organization_params)

    ActiveRecord::Base.transaction do
      @organization.save!
      OrganizationMembership.create!(user: current_user, organization: @organization, role: "admin")
    end

    redirect_to organizations_path, notice: "Organization created"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def show
    @organization = current_user.organizations.find(params[:id])
    @memberships = @organization.organization_memberships.includes(:user)
  end

  def invite
    organization = admin_organization(params[:id])
    email = params[:email].to_s.strip.downcase
    existing_user = User.find_by(email: email)

    if existing_user && organization.users.include?(existing_user)
      redirect_to organization_path(organization), alert: "Already a member"
    elsif existing_user
      OrganizationMembership.create!(user: existing_user, organization: organization, role: "member")
      redirect_to organization_path(organization), notice: "#{email} added"
    else
      OrganizationInvite.find_or_create_by!(organization: organization, email: email)
      redirect_to organization_path(organization), notice: "Invite sent to #{email}"
    end
  end

  def remove_member
    organization = admin_organization(params[:id])
    membership = organization.organization_memberships.find(params[:membership_id])

    if membership.admin? && organization.organization_memberships.where(role: "admin").count <= 1
      redirect_to organization_path(organization), alert: "Cannot remove the last admin"
      return
    end

    removing_self = membership.user == current_user
    membership.destroy!

    if removing_self
      redirect_to organizations_path, notice: "You left #{organization.name}"
    else
      redirect_to organization_path(organization), notice: "Member removed"
    end
  end

  private

  def admin_organization(id)
    organization = current_user.organizations.find(id)
    membership = organization.organization_memberships.find_by(user: current_user)
    raise ActiveRecord::RecordNotFound unless membership&.admin?

    organization
  end

  def organization_params
    params.require(:organization).permit(:name, :slug)
  end
end
