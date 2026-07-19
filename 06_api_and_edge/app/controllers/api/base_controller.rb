module Api
  # Token-authed JSON base. ActionController::API — no cookies, no helpers.
  class BaseController < ActionController::API
    include CurrentScope::Context
    include CurrentScope::Guard
    include CurrentScope::GatingTripwire

    # The JSON denial pattern. The gem's MutationGuard already installs a
    # rescue_from AccessDenied -> `head :forbidden` (empty body); registering
    # our own AFTER Guard wins (rescue_from is searched newest-first), giving
    # API clients a machine-readable body, not just the header.
    rescue_from CurrentScope::AccessDenied do |e|
      response.set_header("X-Current-Scope-Reason", e.reason.to_s) if e.reason
      render json: { error: "forbidden", reason: e.reason }, status: :forbidden
    end

    private

    # config.user_method is :current_user (global) — this base must answer to
    # the same method name the HTML ApplicationController uses.
    def current_user
      @current_user ||= begin
        token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
        User.find_by(api_token: token) if token
      end
    end
  end
end
