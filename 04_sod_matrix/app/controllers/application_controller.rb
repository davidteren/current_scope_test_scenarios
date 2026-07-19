class ApplicationController < ActionController::Base
  include CurrentScope::Context
  include CurrentScope::Guard

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  # Impersonation recipe from the README (scenario 9).
  def true_user = current_user

  def current_scope_user
    return true_user unless session[:impersonated_subject_id]

    User.find_by(id: session[:impersonated_subject_id]) || true_user
  end
end
