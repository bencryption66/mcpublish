class UsersController < WebController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    ActiveRecord::Base.transaction do
      @user.save!
      claim_pending_invites(@user)
    end

    session[:user_id] = @user.id
    redirect_to account_path, notice: "Account created"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def claim_pending_invites(user)
    OrganizationInvite.where(email: user.email).find_each do |invite|
      OrganizationMembership.create!(user: user, organization: invite.organization, role: "member")
      invite.destroy!
    end
  end
end
