Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    resources :dashboard, only: [:index]  # <-- explicitly defined resources
    root to: 'dashboard#index'
    resources :products
    resources :purchase_orders
    resources :users
    resources :reports, only: [:index]
    resources :settings, only: [:index]
  end

  get "up" => "rails/health#show", as: :rails_health_check
  root "home#index"
end

