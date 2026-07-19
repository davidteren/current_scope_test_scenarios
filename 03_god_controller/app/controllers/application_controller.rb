class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_user

  # Host auth MUST register before CurrentScope::Guard is included. Guard's
  # include-time before_action would otherwise run first, turning anonymous
  # traffic into a blank 403 instead of the login redirect (ie-audit P1 / F2).
  before_action :require_login

  include CurrentScope::Context
  include CurrentScope::Guard

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def require_login
    redirect_to sessions_path, alert: "Log in first" unless current_user
  end

  # Friendly denial page instead of the gem default bodyless 403 (ie-audit P1 / F3).
  # JSON/non-HTML clients keep a header-only 403 so API-style probes stay stable.
  def current_scope_render_denied(reason = nil)
    respond_to do |format|
      format.html do
        render template: "shared/access_denied",
               status: :forbidden,
               layout: "application",
               locals: { reason: reason }
      end
      format.any { head :forbidden }
    end
  end
end
