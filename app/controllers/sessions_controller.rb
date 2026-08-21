class SessionsController < WebController
  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)

    if user&.authenticate(params[:password])
      return_to = session[:return_to]
      reset_session
      session[:user_id] = user.id
      redirect_to (return_to || account_path), notice: "Signed in"
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out"
  end
end
