class UsersController < WebController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      claim_pending_invites(@user)
      session[:user_id] = @user.id
      redirect_to account_path, notice: "Account created"
    else
      render :new, status: :unprocessable_entity
    end
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
