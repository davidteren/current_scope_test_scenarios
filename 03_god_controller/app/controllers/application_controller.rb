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
  # HTML and Turbo Stream get the same body (Turbo form posts often negotiate
  # turbo_stream). JSON/non-HTML clients keep a header-only 403 so API-style
  # probes stay stable.
  def current_scope_render_denied(reason = nil)
    respond_to do |format|
      format.html { render_access_denied_page(reason) }
      format.turbo_stream { render_access_denied_page(reason) }
      format.any { head :forbidden }
    end
  end

  def render_access_denied_page(reason)
    # formats: [:html] so turbo_stream requests still resolve the .html.erb
    # template. content_type: text/html so Turbo treats the 403 as a full-page
    # HTML response instead of a stream with no actions (blank UI).
    render template: "shared/access_denied",
           status: :forbidden,
           layout: "application",
           formats: [ :html ],
           content_type: "text/html",
           locals: { reason: reason }
  end
end



