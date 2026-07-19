class SessionsController < ApplicationController
  skip_before_action :current_scope_check!
  skip_before_action :current_scope_mutation_guard!   # sign-in/out ends act-as (README recipe)

  def index
    @users = User.order(:id)
  end

  def create
    session[:user_id] = params[:id]
    session.delete(:impersonated_subject_id)
    redirect_to root_path
  end

  def destroy
    session.delete(:user_id)
    session.delete(:impersonated_subject_id)
    redirect_to root_path
  end
end
