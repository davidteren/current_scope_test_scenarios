class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  include CurrentScope::Context
  include CurrentScope::Guard

  helper_method :current_user
  before_action :require_login

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def require_login
    redirect_to sessions_path, alert: "Log in first" unless current_user
  end
end
