# 📌 **Rails Inventory WebApp Progress Update**

## 🚀 **Project Overview**
This document provides an updated progress report on the Rails Inventory WebApp, including completed tasks, current state, and next steps. The project is being developed using Rails 8.0.1, Ruby 3.2.2, and PostgreSQL, with Devise for authentication and Bootstrap for styling. The development follows an agile approach, with tasks broken down into sprints.

---

## ✅ **Completed Tasks (Sprint 1)**

### **Task 1.1: Configure Devise (Authentication)**
- **Status:** Completed
- **Details:**
  - Devise installed and configured.
  - Custom fields (`role`, `name`, `contact_name`, `phone`, `address`) integrated with Devise.
  - Roles (`admin`, `customer`) implemented and validated.
  - RSpec tests for user sign-up, login/logout, and role assignment implemented and passing.

### **Task 1.2: Set Up Admin Dashboard Controller**
- **Status:** Completed
- **Details:**
  - Admin dashboard controller created under the `admin` namespace.
  - Routes configured for admin dashboard access.
  - Authorization logic implemented to restrict access to admin users only.
  - RSpec tests for dashboard access control (admin vs. non-admin) implemented and passing.

---

## 📌 **Current State**

- **Rails Version:** 8.0.1
- **Ruby Version:** 3.2.3
- **Database:** SQLite (development & test), PostgreSQL (production)
- **Authentication:** Devise with role-based access control (admin, customer).

### **Admin Dashboard**
- **Controller:** `Admin::DashboardController` with `index` action.
- **Authorization:** Only admin users can access the dashboard.
- **Routes:** Namespaced under `admin` with `get 'dashboard', to: 'dashboard#index'`.

### **Testing**
- **RSpec Tests:**
  - Authentication: User registration, login/logout, role assignment.
  - Dashboard Access: Admin access allowed, non-admin access denied.
- **Capybara Tests:** Basic UI integration tests for Bootstrap styles and navigation links.

---

## 📌 **Next Steps (Sprint 1 Remaining Tasks)**

### **Task 1.3: Choose & Set Up CSS Framework**
- **Status:** In Progress
- **Next Steps:**
  - Add Bootstrap gem: `bundle add bootstrap`.
  - Import Bootstrap in `application.scss`: `@import "bootstrap";`.
  - Test Bootstrap installation by adding a simple styled button or navbar to the admin dashboard view.

### **Task 1.4: Admin Dashboard Basic View**
- **Status:** Not Started
- **Next Steps:**
  - Create a clear and simple admin dashboard layout (`app/views/admin/dashboard/index.html.erb`).
  - Integrate responsive layout using Bootstrap classes.
  - Add navigation links for future features (Products, Inventory, Sales Orders, etc.).

### **Task 1.5: Push Changes to GitHub & Deploy to Heroku**
- **Status:** Not Started
- **Next Steps:**
  - Push the `feature/admin-dashboard` branch to GitHub.
  - Merge to `main` via Pull Request.
  - Deploy to Heroku:
    ```bash
    git checkout main
    git pull origin main
    git push heroku main
    heroku run rails db:migrate
    ```

---

## 📌 **Sprint 1 Test Cases (RSpec)**

### **Authentication Tests (Devise)**
- User registration, login, logout.
- Role assignment (admin vs. customer).

### **Dashboard Access Control Tests**
- Admin user access allowed.
- Non-admin users denied (redirected or shown alert).

### **Basic UI Integration Tests (Capybara)**
- Verify Bootstrap styles appear correctly.
- Verify all navigation links are present.

---

## 📌 **Sprint Completion Criteria**

- **Authentication & Authorization:** Fully operational.
- **Admin Dashboard:** Accessible only to admin users.
- **Bootstrap UI Framework:** Successfully integrated and functional.
- **Testing:** All related tests passing.
- **Deployment:** Changes pushed to GitHub and deployed successfully on Heroku.

---

## 📌 **Next Suggested Sprints**

### **Sprint 2: Admin Product Management (CRUD Actions and Views)**
- **Objective:** Implement CRUD operations for product management in the admin dashboard.
- **Tasks:**
  - Create database migrations for products.
  - Implement Product model with validations.
  - Create `Admin::ProductsController` with CRUD actions.
  - Implement views for product management.
  - Write RSpec tests for Product model and controller.

### **Sprint 3: Inventory Management (Individual Item Tracking)**
- **Objective:** Implement inventory management features, including individual item tracking.
- **Tasks:**
  - Create database migrations for inventory.
  - Implement Inventory model with validations.
  - Create `Admin::InventoryController` with CRUD actions.
  - Implement views for inventory management.
  - Write RSpec tests for Inventory model and controller.

### **Sprint 4: Orders Management (Sales & Purchase)**
- **Objective:** Implement order management features for sales and purchase orders.
- **Tasks:**
  - Create database migrations for orders.
  - Implement Order models (SalesOrder, PurchaseOrder) with validations.
  - Create `Admin::OrdersController` with CRUD actions.
  - Implement views for order management.
  - Write RSpec tests for Order models and controller.

### **Sprint 5: Payments & Shipments Tracking**
- **Objective:** Implement payment and shipment tracking features.
- **Tasks:**
  - Create database migrations for payments and shipments.
  - Implement Payment and Shipment models with validations.
  - Create `Admin::PaymentsController` and `Admin::ShipmentsController` with CRUD actions.
  - Implement views for payment and shipment tracking.
  - Write RSpec tests for Payment and Shipment models and controllers.

### **Sprint 6 & 7: Customer Interface (Catalog & Shopping Cart)**
- **Objective:** Implement customer-facing features, including product catalog and shopping cart.
- **Tasks:**
  - Create database migrations for customer-related features.
  - Implement Customer model with validations.
  - Create `Customer::ProductsController` and `Customer::CartController` with necessary actions.
  - Implement views for product catalog and shopping cart.
  - Write RSpec tests for Customer models and controllers.

### **Sprint 8: Security & Performance Optimization, Final Deployment**
- **Objective:** Optimize security and performance, and finalize deployment.
- **Tasks:**
  - Implement security best practices (e.g., SSL, secure headers).
  - Optimize database queries and application performance.
  - Conduct final testing and bug fixes.
  - Deploy the final version to Heroku.

---

## 🚀 **Next step we will start with Sprint 2**
Let's proceed with **Sprint 2: Admin Product Management**. If you have any questions or need further adjustments, please let me know! 🚀

## 🚀 SEO Improvements
- Meta tags for description, canonical URL, and Open Graph have been added to layouts.
- `sitemap_generator` gem generates `sitemap.xml.gz`; run `rake sitemap:generate`.
- `robots.txt` references the sitemap to help search engines crawl the site.

## 🍪 Cookie Banner Configuration
The cookie banner text and button label can be customized, or the banner can be disabled entirely, using environment variables:

- `COOKIE_BANNER_ENABLED` – set to `false` to hide the banner (default: `true`).
- `COOKIE_BANNER_TEXT` – message displayed to users (default shown in Spanish).
- `COOKIE_BANNER_BUTTON_TEXT` – label for the acceptance button (default: `Aceptar`).

These variables allow tailoring the cookie notice to local regulations without changing application code.

---

## 🧾 Inventory Adjustments Ledger (Nueva Funcionalidad)

### Objetivo
Registrar aumentos y disminuciones manuales/físicos de inventario con trazabilidad e idempotencia.

### Entidades Principales
- `InventoryAdjustment` (draft/applied) con campos: `status`, `adjustment_type`, `reference`, `applied_at`, `applied_by_id`, `reversed_at`.
- `InventoryAdjustmentLine` cada línea apunta a un `product`, define `direction` (`increase` | `decrease`), `quantity`, `reason` (para decreases) y `unit_cost` (para increases).
- `InventoryAdjustmentEntry` histórico granular por pieza afectada (creada o cambio de estado).

### Flujo
1. Crear ajuste en estado `draft` sin líneas iniciales.
2. Agregar líneas dinámicamente vía buscador de productos (JS importmap: `inventory_adjustment_lines.js`).
3. Al aplicar (`apply!`):
  - Se genera referencia si falta.
  - Se validan existencias suficientes para todas las disminuciones (se agrupan por producto).
  - Increases: crea nuevas filas en `inventories` con `source = ledger_adjustment` y `adjustment_reference`.
  - Decreases: marca piezas disponibles según FIFO cambiando `status` a uno derivado de `reason` (scrap, marketing, lost, damaged) y agrega `adjustment_reference`.
  - Se recalculan métricas del producto.

### Referencia
Formato: `ADJ-YYYYMM-NN` (ej: `ADJ-202509-01`). El consecutivo se reinicia cada mes por prefijo `YYYYMM`.

### Razones de Decrease → Estado de Inventario
| Reason     | Estado destino |
|-----------|----------------|
| scrap     | scrap          |
| marketing | marketing      |
| lost      | lost           |
| damaged   | damaged        |

### Múltiples líneas del mismo producto
Se permiten múltiples líneas (ej: diferentes razones o costos) y se agrupan sólo para validar stock de disminuciones.

### Nueva columna en `inventories`
`adjustment_reference` para saber qué ajuste creó/modificó la pieza. También se coloca la referencia en `notes` de las piezas creadas.

### Reverse
Implementado (servicio `ReverseInventoryAdjustmentService`) para deshacer: revierte estados / elimina creados (no documentado aquí en detalle aún).

### Tests Clave
- Generación de referencia y secuencia mensual.
- Aplicación con múltiples líneas mismo producto (increase + decrease).
- Validación de stock insuficiente agrupando decreases.

### Próximas Mejores
- Parametrizar patrón de referencia vía variable de sistema.
- Endpoint JSON para auditoría rápida.
- Paginación / filtros por razón.

---