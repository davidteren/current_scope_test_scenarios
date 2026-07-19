# Simulates a common host pattern: a catch-all StandardError rescue registered
# AFTER the CurrentScope includes (which live in ApplicationController).
class LegacyController < ApplicationController
  rescue_from StandardError, with: :render_error_page

  def show = render(plain: "legacy ok")

  private

  def render_error_page = render(plain: "our custom 500 page", status: :internal_server_error)
end
