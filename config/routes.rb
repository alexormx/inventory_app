Rails.application.routes.draw do
  get "pages/privacy_notice"
  get "carts/show"
  get "products/index"
  get "products/show"
  post "/accept_cookies", to: "users#accept_cookies", as: :accept_cookies
  # Devise authentication for all users
  devise_for :users

  # Admin namespace
  namespace :admin do
    resources :visitor_logs, only: [:index]

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
    get 'dashboard/profitable', to: 'dashboard#profitable', as: :dashboard_profitable
    get 'dashboard/inventory_top', to: 'dashboard#inventory_top', as: :dashboard_inventory_top
  get 'dashboard/categories_rank', to: 'dashboard#categories_rank', as: :dashboard_categories_rank
  get 'dashboard/customers_rank', to: 'dashboard#customers_rank', as: :dashboard_customers_rank
  # Geo stats for dashboard (JSON)
  get 'dashboard/geo', to: 'dashboard#geo', as: :dashboard_geo
    # Tablas/frames del dashboard (Turbo)
    get 'dashboard/sellers', to: 'dashboard#sellers', as: :dashboard_sellers

    # Product Management
    get 'products/drafts', to: 'products#drafts', as: :products_drafts
    get 'products/active', to: 'products#active', as: :products_active
    get 'products/inactive', to: 'products#inactive', as: :products_inactive

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

  # Deprecated standalone User Management (migrated to unified Users tabs)
  # resources :customers
  # resources :suppliers, only: [:index, :new, :create, :edit, :update]
  # resources :admins,   only: [:index, :new, :create, :edit, :update]

    # Purchase Orders
    resources :purchase_orders do
      patch :confirm_receipt, on: :member
    end

    # Reports & Settings
    resources :reports, only: [:index] do
      collection do
        get :inventory_items
      end
    end
    resources :settings, only: [:index] do
      collection do
        post :index # para guardar configuraciones simples (tax)
        post :sync_inventory_statuses
        post :backfill_sale_orders_totals
        get  :delivered_orders_debt_audit
        post :run_delivered_orders_debt_audit
        # Permitir GET directo (fallback) para evitar errores si el usuario refresca la URL POST
        get  :run_delivered_orders_debt_audit, to: redirect("/admin/settings/delivered_orders_debt_audit")
        post :reset_product_dimensions
  post :recalc_all_po_alpha_costs
      end
    end

    # General user management (admin-facing) con tabs
  resources :users, only: [:index, :new, :create, :edit, :update] do
      collection do
        get :customers
        get :suppliers
        get :admins
      end
      resources :shipping_addresses, controller: 'user_shipping_addresses' do
        member do
          patch :make_default
        end
      end
    end

    # Payments Management
    resources :payments, only: [:create]

  # Preventas y 'sobre pedido'
  get 'preorders', to: 'preorders#index', as: :preorders

    # Sales Order Management
    resources :sale_orders do
      resources :sales_order_items, only: [:create, :update, :destroy]
      resources :payments, only: [:new, :create, :edit, :update, :destroy]
  resources :shipments, only: [:new, :create, :edit, :update, :destroy]
      member do
        get :summary
      end
    end

  end
  # Public product views
  get '/catalog', to: 'products#index', as: :catalog
  resources :products, only: [:show]

  # Shopping Cart routes
  resources :cart_items, only: [:create, :update, :destroy]
  get "/cart", to: "carts#show", as: :cart

  # Customer shipping addresses
  resources :shipping_addresses, only: [:index, :new, :create, :edit, :update, :destroy] do
    member do
      patch :make_default
    end
  end

  #checkout process with multiple steps
  get '/checkout/step1', to: 'checkouts#step1', as: :checkout_step1
  post '/checkout/step1', to: 'checkouts#step1_submit'

  get '/checkout/step2', to: 'checkouts#step2', as: :checkout_step2
  post '/checkout/step2', to: 'checkouts#step2_submit'

  get '/checkout/step3', to: 'checkouts#step3', as: :checkout_step3
  post '/checkout/complete', to: 'checkouts#complete', as: :checkout_complete

  get "/checkout/thank_you", to: "checkouts#thank_you", as: :checkout_thank_you

  # Customer orders
  resources :orders, only: [:index, :show] do
    member do
      get :summary
    end
  end

  # Static pages
  get "/aviso-de-privacidad", to: "pages#privacy_notice", as: :privacy_notice
  get "/terminos-y-condiciones", to: "pages#terms", as: :terms

  namespace :api do
    namespace :v1 do
      resources :products, only: [:create]
      get 'products/exists', to: 'products#exists'
      resources :users, only: [:create]
      get 'users/exists', to: 'users#exists'
      resources :purchase_orders, only: [:create]
    resources :sales_orders, only: [:create, :update] do
        member do
          post :recalculate_and_pay
      post :ensure_payment
        end
      end
      # Pagos asociados a Sale Orders
      resources :sales_orders, only: [] do
        resources :payments, only: [:create]
      end
  # Items via API: batch-only
  post 'purchase_order_items/batch', to: 'purchase_order_items#batch'
  post 'sale_order_items/batch', to: 'sale_order_items#batch'
    end
  end

  # Simple API (unversioned) for postal codes autofill
  get '/api/postal_codes', to: 'api/postal_codes#index'

  # Rails health check (uptime monitor, etc.)
  get "up" => "rails/health#show", as: :rails_health_check

  # Public-facing root (if any)
  root "home#index"
end