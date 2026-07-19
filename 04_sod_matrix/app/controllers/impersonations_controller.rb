# README act-as recipe. create is gated by Guard (impersonations#create is a
# routed permission); destroy must skip the mutation guard or act-as could
# never end.
class ImpersonationsController < ApplicationController
  skip_before_action :current_scope_mutation_guard!, only: :destroy

  def create
    session[:impersonated_subject_id] = params.expect(:subject_id)
    redirect_to root_path
  end

  def destroy
    session.delete(:impersonated_subject_id)
    redirect_to root_path
  end
end
