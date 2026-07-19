# Completely non-resourceful controller: plain get/post routes, no model.
class WizardController < ApplicationController
  def step_one = render(plain: "wizard step one")

  def submit_step_one
    session[:wizard_step_one] = params[:answer]
    redirect_to wizard_step_two_path
  end

  def step_two = render(plain: "wizard step two (answer: #{session[:wizard_step_one]})")

  def complete
    session.delete(:wizard_step_one)
    render plain: "wizard complete"
  end
end
