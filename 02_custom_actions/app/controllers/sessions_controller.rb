class SessionsController < ApplicationController
  skip_before_action :current_scope_check!

  def index
    @users = User.order(:id)
  end

  def create
    session[:user_id] = params[:user_id]
    redirect_to reports_path
  end

  def destroy
    session.delete(:user_id)
    redirect_to root_path
  end
end
