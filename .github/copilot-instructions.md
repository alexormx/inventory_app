# Rails Inventory Management System - Copilot Instructions

## Project Overview
This is a comprehensive Rails 8.0.1 inventory management system for a hobby store ("Pasatiempos"), built with Ruby 3.2.3. The app manages products, purchase/sales orders, individual inventory tracking, and customer orders with a multi-role admin dashboard.

## Architecture Patterns

### Service-Oriented Design
Business logic lives in services under `app/services/`, not controllers or models:
- `ApplyInventoryAdjustmentService` - Handles inventory adjustments with atomicity and FIFO
- `Products::UpdateStatsService` - Recalculates product metrics after inventory changes
- Services follow the pattern: `initialize(params)` → `call` method → return value or raise exception

### Individual Inventory Tracking
Unlike simple stock counts, each physical item is tracked individually in the `inventories` table:
- Each inventory record represents one physical piece with status: `available`, `reserved`, `sold`, `in_transit`, `damaged`, `lost`, `scrap`, `marketing`
- FIFO logic for decreases: oldest available items are consumed first
- Inventory sync rules automatically create/destroy records when PO/SO items change quantities

### Admin-First Design
The app is admin-centric with a customer-facing catalog. Admin namespace (`/admin/*`) contains the primary functionality:
- Dashboard with ECharts visualizations (`app/controllers/admin/dashboard_controller.rb`)
- Comprehensive product, order, and inventory management
- Audit tools for data consistency checking and fixing

### State-Based Workflows
Critical entities use enum states with service-managed transitions:
- `InventoryAdjustment`: `draft` → `applied` (with reverse capability)
- Orders have status progressions managed by dedicated services
- Inventory items track status changes with timestamps

## Key Development Workflows

### TDD & Branch-Based Development
**Always follow Test-Driven Development:**
1. Create a new branch for every feature/fix: `git checkout -b feature/description`
2. Write failing tests first (Red)
3. Implement minimal code to pass (Green)
4. Refactor while keeping tests green (Refactor)
5. Only merge to main after all tests pass and feature is confirmed working

```bash
# TDD workflow commands
git checkout -b feature/new-feature
bundle exec rspec  # Should have failing tests
# Implement feature
bundle exec rspec  # Should pass
git add . && git commit -m "Add feature with tests"
git checkout main && git merge feature/new-feature
git push origin main
```

### Testing Strategy
```bash
# Run full test suite (always before merging)
bundle exec rspec

# Focus on specific areas during development
bundle exec rspec spec/services/  # Business logic
bundle exec rspec spec/system/    # UI workflows
bundle exec rspec spec/requests/  # API endpoints

# Run specific test file during TDD cycle
bundle exec rspec spec/services/apply_inventory_adjustment_service_spec.rb
```

Test data uses FactoryBot with inventory control:
```ruby
# Default: creates 5 available inventory units
product = create(:product)

# No auto-inventory (for adjustment tests)
product = create(:product, skip_seed_inventory: true)
```

### Asset Pipeline
Uses esbuild with importmap for JavaScript:
```bash
npm run build:watch  # Development
npm run build:prod   # Production
```

Stimulus controllers in `app/javascript/controllers/` handle dynamic UI (product search, line item management).

### Database Migrations
Always run after pulling:
```bash
bin/rails db:migrate
bin/rails db:test:prepare
```

## Critical Business Rules

### Inventory Adjustments Ledger
- Only two states: `draft` (editable) and `applied` (immutable)
- Reference format: `ADJ-YYYYMM-NN` (e.g., `ADJ-202509-01`)
- Increases create new inventory; decreases mark existing as damaged/lost/scrap via FIFO
- Idempotent: `adjustment.apply!` is safe to call multiple times
- Reversible: `adjustment.reverse!` undoes changes and returns to draft state

### Order-Inventory Sync
- `PurchaseOrderItem` changes auto-sync to create/destroy inventory records
- `SaleOrderItem` changes auto-reserve available inventory (newest first)
- Sync scoped per line item to prevent cross-contamination

### API Design
RESTful APIs under `/api/v1/` with batch endpoints:
- Single item: `POST /api/v1/purchase_order_items`
- Bulk: `POST /api/v1/purchase_order_items/batch`
- Product lookup by SKU or ID supported
- Returns `201` on success with `{ status: "ok", id: <id> }`

## Security & Authorization
- Devise authentication with role-based access (`admin`, `customer`)
- Admin actions require `authorize_admin!` in controllers
- API endpoints use token authentication via `authenticate_with_token!`

## Common Gotchas
- Don't modify inventory directly; use services that handle sync and metrics
- Test environment needs `config.enable_reloading = true` to avoid FrozenError
- System variables are stored in DB table, access via `SystemVariable.get(key, default)`
- Product dimensions and costs auto-update based on most recent purchase order

## Performance Considerations
- Product stats are denormalized and updated via services after inventory changes
- ECharts dashboard data is cached and served as JSON endpoints
- Kaminari pagination on large tables (products, inventory, orders)
- Redis caching for session data and background jobs

## Debugging Tips
- Use `bin/rails zeitwerk:check` for autoloading issues
- Check `log/development.log` for service errors and SQL queries
- Admin audit pages highlight data inconsistencies automatically
- Inventory status changes are timestamped for troubleshooting workflows