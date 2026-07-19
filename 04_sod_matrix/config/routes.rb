Rails.application.routes.draw do
  mount CurrentScope::Engine => "/current_scope"

  root "sessions#index"
  post "login/:id" => "sessions#create", as: :login
  delete "logout" => "sessions#destroy", as: :logout

  post "impersonation" => "impersonations#create", as: :impersonation
  delete "impersonation" => "impersonations#destroy"

  resources :expenses do
    member do
      post :approve
      post :reject
    end
    collection { post :approve_all }
  end

  resources :invoices, only: [ :index, :show ] do
    member { post :approve }
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
