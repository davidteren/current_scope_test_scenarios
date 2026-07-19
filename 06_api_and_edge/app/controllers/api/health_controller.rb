module Api
  # Public health endpoint: NO Guard (never gated), tripwire included with the
  # health action explicitly marked public. `boom` is deliberately NOT marked —
  # simulates a forgotten Guard include on a new ungated base (tripwire case b).
  class HealthController < ActionController::API
    include CurrentScope::GatingTripwire
    current_scope_skip_tripwire! only: :health

    def health
      render json: { ok: true }
    end

    def boom
      render json: { leaked: "this action is ungated and unmarked" }
    end
  end
end
