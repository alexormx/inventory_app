# frozen_string_literal: true

Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  get 'pages/privacy_notice'
  get 'carts/show'
  get 'products/index'
  get 'products/show'
  post '/accept_cookies', to: 'users#accept_cookies', as: :accept_cookies

  # Newsletter subscription
  resources :newsletter_subscribers, only: [:create]

  # User profile
  resource :profile, only: %i[show edit update]

  # Devise authentication for all users
  devise_for :users

  # Admin namespace
  namespace :admin do
    # Quick Add Collectible (producto usado + inventario en un paso)
    get 'collectibles/quick_add', to: 'collectibles#quick_add', as: :collectibles_quick_add
    post 'collectibles/quick_add', to: 'collectibles#create_quick_add'
    get 'collectibles/search_products', to: 'collectibles#search_products', as: :collectibles_search_products

    # Sales Orders Audit
    get 'sale_orders_audit', to: 'sale_orders_audits#index', as: :sale_orders_audit
    post 'sale_orders_audit/fix', to: 'sale_orders_audits#fix_gaps', as: :sale_orders_audit_fix
    # Fallback (si alguien hace GET por error, redirigir al índice)
    get  'sale_orders_audit/fix', to: redirect('/admin/sale_orders_audit')
    # Inventory Audit
    get 'inventory_audit', to: 'inventory_audits#index', as: :inventory_audit
    post 'inventory_audit/fix', to: 'inventory_audits#fix_inconsistencies', as: :inventory_audit_fix
    post 'inventory_audit/fix_missing_so_lines', to: 'inventory_audits#fix_missing_so_lines',
                                                 as: :inventory_audit_fix_missing_so_lines
    post 'inventory_audit/auto_assign', to: 'inventory_audits#auto_assign', as: :inventory_audit_auto_assign
    # Inventory Events (audit trail de cambios de costo / desvinculaciones)
    resources :inventory_events, only: [:index]
    # Inventory reconciliation trigger
    resources :inventory_reconciliations, only: [:create]
    # Preorders audit
    get  'preorders_audit', to: 'preorders_audits#index', as: :preorders_audit
    post 'preorders_audit/fix', to: 'preorders_audits#fix', as: :preorders_audits_fix
    resources :visitor_logs, only: [:index]

    # Inventory Management views
    get 'inventory', to: 'inventory#index', as: :inventory
    get 'inventory/location_explorer', to: 'inventory#location_explorer', as: :inventory_location_explorer
    get 'inventory/unlocated', to: 'inventory#unlocated', as: :inventory_unlocated
    get 'inventory/unlocated_items/:product_id', to: 'inventory#unlocated_items', as: :inventory_unlocated_items
    post 'inventory/bulk_assign_location', to: 'inventory#bulk_assign_location', as: :inventory_bulk_assign_location
    get 'inventory/location_contents/:location_id', to: 'inventory#location_contents', as: :inventory_location_contents
    get 'inventory/transfer', to: 'inventory#transfer', as: :inventory_transfer
    get 'inventory/location_items/:location_id', to: 'inventory#location_items', as: :inventory_location_items
    post 'inventory/execute_transfer', to: 'inventory#execute_transfer', as: :inventory_execute_transfer
    resources :inventory do
      member do
        get :items
        get :edit_status
        patch :update_status
        get :cancel_edit_status
        get :edit_location
        patch :update_location
        get :cancel_edit_location
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

    # Inventory Locations (Warehouse Management)
    resources :inventory_locations do
      member do
        get :children
      end
      collection do
        get :tree
        get :options
        get :search
      end
    end

    # Location Types (configurable types for inventory locations)
    resources :location_types, except: [:show] do
      member do
        patch :move
      end
    end

    # Product Management
    get 'products/drafts', to: 'products#drafts', as: :products_drafts
    get 'products/active', to: 'products#active', as: :products_active
    get 'products/inactive', to: 'products#inactive', as: :products_inactive

    resources :products do
      # Activar / Desactivar productos
      member do
        patch :activate
        patch :deactivate
        post  :assign_preorders
        post  :discontinue
        post  :reverse_discontinue
      end
      # Image removal for ActiveStorage
      delete 'images/:image_id', to: 'products#purge_image', as: :purge_image

      # Product search as JSON
      collection do
        get 'search'
      end
    end

    # Deprecated standalone User Management (migrated to unified Users tabs)
    # resources :customers
    # resources :suppliers, only: [:index, :new, :create, :edit, :update]
    # resources :admins,   only: [:index, :new, :create, :edit, :update]

    # Purchase Orders
    resources :purchase_orders do
      patch :confirm_receipt, on: :member
      get :summary, on: :member
      collection do
        get :line_audit
        post :rebalance_all_mismatches
      end
      post :rebalance_inventory, on: :member
    end

    # Reports & Settings
    resources :reports, only: [:index] do
      collection do
        get :inventory_items
        get :inventory_items_with_locations
        get :cancellations
      end
    end
    # Accounts Receivable simple report
    resources :receivables, only: [:index]

    # Shipping & Payment Methods Management
    resources :shipping_methods, except: [:show] do
      member do
        patch :toggle_active
      end
    end
    resources :payment_methods, except: [:show] do
      member do
        patch :toggle_active
      end
    end

    resources :settings, only: [:index] do
      collection do
        post :index # para guardar configuraciones simples (tax)
        post :sync_inventory_statuses
        post :backfill_sale_orders_totals
        post :backfill_inventory_sale_order_item_id
        get  :delivered_orders_debt_audit
        post :run_delivered_orders_debt_audit
        # Permitir GET directo (fallback) para evitar errores si el usuario refresca la URL POST
        get  :run_delivered_orders_debt_audit, to: redirect('/admin/settings/delivered_orders_debt_audit')
        post :reset_product_dimensions
        post :recalc_all_po_alpha_costs
        post :mark_distributed_costs
      end
    end

    # System variables explorer
    resources :system_variables, only: %i[index create update]

    # General user management (admin-facing) con tabs
    resources :users, only: %i[index new create edit update] do
      collection do
        get :customers
        get :suppliers
        get :admins
        get :suggest
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
    post 'preorders/assign_now', to: 'preorders#assign_now', as: :preorders_assign_now
    delete 'preorders/:id', to: 'preorders#destroy', as: :preorder
    post   'preorders/:id/cancel', to: 'preorders#cancel', as: :preorder_cancel

    # Sales Order Management
    resources :sale_orders do
      resources :sales_order_items, only: %i[create update destroy]
      resources :payments, only: %i[new create edit update destroy]
      resources :shipments, only: %i[new create edit update destroy]
      member do
        get :summary
        post :cancel
        get :prepare
        post :ship
        post :deliver
        post :force_pending, to: 'sale_orders_status#force_pending'
        post :force_delivered, to: 'sale_orders_status#force_delivered'
        post :cancel_reservations, to: 'sale_orders#cancel_reservations'
        post :reassign, to: 'sale_orders#reassign'
      end
    end

    # Inventory Adjustments (Ledger)
    resources :inventory_adjustments do
      post :apply, on: :member
      post :reverse, on: :member
    end
  end
  # Public product views
  get '/catalog', to: 'products#index', as: :catalog
  resources :products, only: [:show]

  # Shopping Cart routes
  resources :cart_items, only: %i[create update destroy]
  get '/cart', to: 'carts#show', as: :cart

  # Customer shipping addresses
  resources :shipping_addresses, only: %i[index new create edit update destroy] do
    member do
      patch :make_default
    end
  end

  # checkout process with multiple steps
  get '/checkout/step1', to: 'checkouts#step1', as: :checkout_step1
  post '/checkout/step1', to: 'checkouts#step1_submit'

  get '/checkout/step2', to: 'checkouts#step2', as: :checkout_step2
  post '/checkout/step2', to: 'checkouts#step2_submit'

  get '/checkout/step3', to: 'checkouts#step3', as: :checkout_step3
  post '/checkout/complete', to: 'checkouts#complete', as: :checkout_complete

  get '/checkout/thank_you', to: 'checkouts#thank_you', as: :checkout_thank_you

  # Customer orders
  resources :orders, only: %i[index show] do
    member do
      get :summary
    end
  end

  # Static pages
  get '/aviso-de-privacidad', to: 'pages#privacy_notice', as: :privacy_notice
  get '/terminos-y-condiciones', to: 'pages#terms', as: :terms

  namespace :api do
    namespace :v1 do
      resources :products, only: [:create]
      get 'products/exists', to: 'products#exists'
      resources :users, only: [:create]
      get 'users/exists', to: 'users#exists'
      resources :purchase_orders, only: [:create]
      resources :sales_orders, only: %i[create update] do
        member do
          post :recalculate_and_pay
          post :ensure_payment
        end
      end
      # Pagos asociados a Sale Orders
      resources :sales_orders, only: [] do
        resources :payments, only: [:create]
      end
      # Items via API
      resources :purchase_order_items, only: [:create] do
        collection do
          post :batch
        end
      end
      resources :sale_order_items, only: [:create] do
        collection do
          post :batch
        end
      end
    end
  end

  # Health check (lightweight; avoids hitting DB on boot)
  get 'up' => 'health#show', as: :rails_health_check

  # Sitemap for search engines (dynamically generated)
  get 'sitemap.xml', to: 'sitemaps#show', as: :sitemap, defaults: { format: :xml }

  # Public-facing root (if any)
  root 'home#index'
end
