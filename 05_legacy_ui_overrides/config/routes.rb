Rails.application.routes.draw do
  # Probe 4: engine mounted at a CUSTOM path, not the default /current_scope.
  mount CurrentScope::Engine => "/permissions"

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
  get "dashboard", to: "dashboard#show"

  resources :reports

  namespace :admin do
    resources :reports do
      member { post :approve }
    end
  end

  resources :sessions, only: [ :index, :create, :destroy ]
end
