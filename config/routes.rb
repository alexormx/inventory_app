Rails.application.routes.draw do
  get "carts/show"
  get "products/index"
  get "products/show"
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
      # Activar / Desactivar productos
      member do
        patch :activate
        patch :deactivate
      end
      # Image removal for ActiveStorage
      delete "images/:image_id", to: "products#purge_image", as: :purge_image

      # Product search as JSON
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

    # Payments Management
    resources :payments, only: [:create]

    # Sales Order Management
    resources :sale_orders do
      resources :sales_order_items, only: [:create, :update, :destroy]
      resources :payments, only: [:new, :create, :edit, :update, :destroy]
      resources :shipments, only: [:new, :create, :edit, :update]
    end

  end
  # Public product views
  get '/catalog', to: 'products#index', as: :catalog
  resources :products, only: [:show]

  # Shopping Cart routes
  resources :cart_items, only: [:create]
  get "/cart", to: "carts#show", as: :cart

  # Rails health check (uptime monitor, etc.)
  get "up" => "rails/health#show", as: :rails_health_check

  # Public-facing root (if any)
  root "home#index"
end