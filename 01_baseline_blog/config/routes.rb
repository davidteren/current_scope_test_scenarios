Rails.application.routes.draw do
  resources :comments
  resources :posts
  resources :sessions, only: [ :index, :create ]
  delete "logout", to: "sessions#destroy", as: :logout
  get "about", to: "about#show"
  mount CurrentScope::Engine => "/current_scope"

  get "up" => "rails/health#show", as: :rails_health_check

  root "posts#index"
end
