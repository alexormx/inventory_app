Rails.application.routes.draw do
  # Devise authentication for all users
  devise_for :users

  # Admin namespace
  namespace :admin do

    #Inventory Management views
    get "inventory", to: "inventory#index", as: :inventory
    resources :inventory do      
      member do
        get :items
        get :edit_status
        patch :update_status
        get :cancel_edit_status
      end   
    end
    
    # Admin Dashboard
    get 'dashboard', to: 'dashboard#index', as: :dashboard

    # Product Management
    resources :products do
      # Image removal for ActiveStorage
      delete "images/:image_id", to: "products#purge_image", as: :purge_image

      # Product serach as JSON
      collection do
        get "search"
      end
    end

    # Customer Management
    resources :customers

    # Supplier & Admin User Management
    resources :suppliers, only: [:index, :new, :create, :edit, :update]
    resources :admins, only: [:index, :new, :create, :edit, :update]

    # Purchase Orders
    resources :purchase_orders do 
      patch :confirm_receipt, on: :member
    end

    # Reports & Settings
    resources :reports, only: [:index]
    resources :settings, only: [:index]

    # General user management (admin-facing)
    resources :users

  end

  # Rails health check (uptime monitor, etc.)
  get "up" => "rails/health#show", as: :rails_health_check

  # Public-facing root (if any)
  root "home#index"
end