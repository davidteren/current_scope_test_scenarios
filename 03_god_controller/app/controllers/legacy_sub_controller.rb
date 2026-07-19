# Probe 7: inherits actions from the god controller but has its own
# controller_path ("legacy_sub"), so the same code is a DIFFERENT permission.
class LegacySubController < LegacyController
  # dashboard and stats are inherited from LegacyController.

  def only_here
    render json: { sub: true }
  end
end
