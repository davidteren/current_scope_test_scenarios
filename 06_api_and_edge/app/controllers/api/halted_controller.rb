module Api
  # Tripwire blind spot (documented): rendering from a before_action halts the
  # chain, so the tripwire's after_action never runs.
  class HaltedController < ActionController::API
    include CurrentScope::GatingTripwire

    before_action { render json: { leaked_from_before_action: true } }

    def secret
      render json: { never: "reached" }
    end
  end
end
