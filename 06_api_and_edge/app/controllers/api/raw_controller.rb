module Api
  # Deliberately does NOT inherit Api::BaseController: observes the gem's
  # OUT-OF-BOX denial rendering on ActionController::API (no custom rescue).
  class RawController < ActionController::API
    include CurrentScope::Context
    include CurrentScope::Guard

    def show
      render json: { secret: true }
    end

    private

    def current_user
      token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
      User.find_by(api_token: token) if token
    end
  end
end
