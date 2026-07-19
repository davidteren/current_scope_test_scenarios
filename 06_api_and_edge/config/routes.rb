Rails.application.routes.draw do
  mount CurrentScope::Engine => "/current_scope"

  root "sessions#index"
  resources :sessions, only: [ :index, :create ]
  delete "logout" => "sessions#destroy", as: :logout
  resources :items, only: [ :index ]

  # --- Routing edge cases under probe ---
  # (a) pure rack route, no controller
  get "ping", to: proc { [ 200, { "Content-Type" => "text/plain" }, [ "pong" ] ] }
  # (b) route to a controller that does not exist
  get "ghosts" => "ghosts#index"
  # (c1) constrained route
  constraints ->(req) { req.params[:beta] == "1" } do
    get "beta_items" => "items#index"
  end
  # (c2) scoped module route
  scope module: :api do
    get "modscoped_health" => "health#health"
  end
  # (c3) redirect route
  get "old" => redirect("/new")
  # (d) second path to the SAME controller#action — dedupe check
  get "items_alias" => "items#index"

  # OPTIONS routed to a gated action — how does the gate treat the verb?
  match "cors_probe" => "items#index", via: :options

  namespace :api do
    get "health" => "health#health"
    get "boom" => "health#boom"
    get "halted" => "halted#secret"
    get "raw" => "raw#show"

    namespace :v1 do
      resources :items, only: [ :index, :show, :create, :destroy ] do
        member { post :publish }
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
