class ApplicationController < ActionController::Base
  include CurrentScope::Context
  include CurrentScope::Guard

  helper_method :current_user

  # Probe 9: the branded host 403 page. Declared AFTER `include Guard` so it
  # takes precedence over the rescue_from(head :forbidden) that MutationGuard
  # silently installs on this class.
  rescue_from CurrentScope::AccessDenied do |exception|
    @permission = exception.message
    @reason = exception.reason
    response.set_header("X-Current-Scope-Reason", @reason.to_s) if @reason
    render "errors/forbidden", status: :forbidden
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
