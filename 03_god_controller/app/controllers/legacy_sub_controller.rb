# Probe 7: inherits actions from the god controller but has its own
# controller_path ("legacy_sub"), so the same code is a DIFFERENT permission.
class LegacySubController < LegacyController
  # dashboard and stats are inherited from LegacyController.

  def only_here
    render json: { sub: true }
  end

  private

  # Parent skips the gate for dashboard when skip_dashboard_gate? is true.
  # Keep legacy_sub#dashboard enforced — it is a different permission key
  # (ie-audit P1 / F5 host fix). Do NOT redeclare before_action :current_scope_check!
  # with only: here; that would narrow Guard's callback for every subclass action.
  def skip_dashboard_gate?
    false
  end
end
