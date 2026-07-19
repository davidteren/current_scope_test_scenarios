module Admin
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_admin!

    private

    def require_admin!
      return if current_user&.admin?

      render plain: "Admins only (host admin flag)", status: :forbidden
    end
  end
end
