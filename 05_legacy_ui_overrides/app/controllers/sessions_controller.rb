class SessionsController < ApplicationController
  skip_before_action :current_scope_check!

  def index
    @users = User.all
  end

  def create
    session[:user_id] = params[:user_id]
    redirect_to root_path
  end

  def destroy
    session.delete(:user_id)
    redirect_to sessions_path
  end
end
