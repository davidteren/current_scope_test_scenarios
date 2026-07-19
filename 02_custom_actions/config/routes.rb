Rails.application.routes.draw do
  mount CurrentScope::Engine => "/current_scope"

  get "up" => "rails/health#show", as: :rails_health_check

  root "sessions#index"
  resources :sessions, only: %i[index create]
  delete "logout" => "sessions#destroy", as: :logout

  # match via GET+POST — must precede resources :reports or GET /reports/search
  # would hit reports#show with id="search".
  match "reports/search" => "reports#search", via: %i[get post], as: :search_reports

  resources :reports do
    member do
      post  :approve
      post  :reject
      post  :publish
      patch :archive
      post  :clone
    end
    collection do
      get  :export
      post :bulk_archive
      get  :preview_all
    end
  end

  get "legacy" => "legacy#show"

  # Completely non-resourceful controller, plain get/post routes.
  get  "wizard/step_one"        => "wizard#step_one"
  post "wizard/submit_step_one" => "wizard#submit_step_one"
  get  "wizard/step_two"        => "wizard#step_two"
  post "wizard/complete"        => "wizard#complete"
end
