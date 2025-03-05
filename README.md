
# 📌 **Rails Database Migration, Models, RSpec Testing & Gemfile Summary**

## **1️⃣ Overview**
This document outlines all the steps taken to set up and migrate the database for the Rails 8.0.1 application, including Devise authentication, database structure, model relationships, RSpec testing, and required gems.

---

## **2️⃣ Required Gems & Their Purpose**

### **🔹 Core Framework & Dependencies**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `rails` | `~> 8.0.1` | Core framework for building web applications in Ruby. |
| `puma` | `>= 5.0` | High-performance web server for running Rails applications. |
| `pg` | `~> 1.1` | PostgreSQL adapter for Active Record, used as the database. |
| `propshaft` | | Modern asset pipeline for Rails applications. |

### **🔹 Frontend & JavaScript Support**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `importmap-rails` | | Enables JavaScript ESM import maps without Webpack. |
| `turbo-rails` | | Hotwire’s Turbo for fast page updates and SPA-like navigation. |
| `stimulus-rails` | | JavaScript framework for managing UI interactions. |
| `tailwindcss-rails` | | Integrates Tailwind CSS for styling Rails applications. |

### **🔹 Authentication & Security**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `devise` | `~> 4.9` | User authentication, session management, and password recovery. |
| `brakeman` | | Security scanner for finding vulnerabilities in Rails apps. |

### **🔹 Caching & Performance**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `solid_cache` | | Caching mechanism for Rails applications. |
| `solid_queue` | | Background job system for handling asynchronous tasks. |
| `solid_cable` | | WebSockets for real-time features using ActionCable. |
| `bootsnap` | | Caches expensive operations to reduce application boot time. |

### **🔹 Database & API Support**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `jbuilder` | | Allows easy generation of JSON APIs in Rails. |

### **🔹 Deployment & Production Enhancements**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `kamal` | | Docker-based deployment tool for Rails applications. |
| `thruster` | | Adds HTTP caching, compression, and X-Sendfile acceleration. |

### **🔹 Development & Debugging**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `debug` | | Debugging tool for Rails applications. |
| `dotenv-rails` | | Manages environment variables securely. |
| `rubocop-rails-omakase` | | Omakase-style Ruby linting and code style enforcement. |
| `web-console` | | Allows interactive Rails console access from error pages. |

### **🔹 Testing Frameworks**
| Gem | Version | Purpose & Usage |
|------|---------|----------------|
| `rspec-rails` | | Core RSpec framework for unit testing in Rails. |
| `capybara` | | Feature testing framework for simulating user interactions. |
| `selenium-webdriver` | | Enables browser automation for system tests. |
| `webdrivers` | `5.0.0` | Manages and updates browser drivers automatically. |
| `rails-controller-testing` | `1.0.5` | Adds support for controller tests in RSpec. |
| `shoulda-matchers` | `~> 5.0` | Simplifies testing of models and associations. |

---

## **3️⃣ Database Tables Created & Adjustments**
### **✅ Tables Created:**

1. **`users`**
   - **Devise authentication implemented.**
   - **Role-based authorization:** Roles include `admin`, `customer`, and `supplier`.
   - **Wholesale customers:** Introduced `discount_rate` for wholesale customers.
   - **Column `user_type` renamed to `role` for clarity.**
   - **Constraints:**
     - `email`: unique, required
     - `name`: required
     - `role`: required, default `customer`

2. **`products`**
   - **New columns:**
     - `discount_limited_stock` to control how many products can be sold at a discounted rate.
     - `maximum_discount` to define the highest possible discount.
     - `barcode` is now optional.
   - **Constraints:**
     - `product_sku`: unique, required
     - `selling_price`: required
     - `supplier_id`: foreign key references `users`

3. **`inventory`**
   - **Each row represents an individual product unit.**
   - Tracks **purchase cost and sale cost per item**.
   - **Status-based tracking:** `Available`, `Reserved`, `Sold`, `Lost`, `Damaged`, `Scrap`, `In Transit`.
   - **Stores `purchase_order_id` and `sale_order_id` instead of separate order items tables.**
   - **Constraints:**
     - `product_id`: required, foreign key
     - `purchase_cost`: required, numeric
     - `status`: required

4. **`purchase_orders`**
   - **Handles supplier orders.**
   - **Backorders are supported.**
   - **Purchase orders split when partial shipments occur.**
   - **Updated Columns:**
     - Added `shipping_cost`, `tax_cost`, and `other_cost`.
   - **Constraints:**
     - `id`: primary key (string)
     - `user_id`: foreign key
     - `subtotal`, `total_order_cost`: required, numeric
     - `status`: required

5. **`sale_orders`**
   - **Handles customer orders.**
   - **Linked to `payments` and `shipments` tables.**
   - **Constraints:**
     - `id`: primary key (string)
     - `user_id`: foreign key
     - `subtotal`, `total_order_value`: required, numeric
     - `status`: required

6. **`payments`**
   - **Tracks customer payments.**
   - **New `status` column** to track `Pending`, `Completed`, `Refunded`, etc.
   - **Constraints:**
     - `amount`: required, numeric
     - `payment_method`: required
     - `status`: required
     - `sale_order_id`: foreign key (added in separate migration)

7. **`shipments`**
   - **Tracks shipments for both sales and purchases.**
   - **New columns:** `last_update` (timestamp) & `status` (e.g., Pending, Shipped, Delivered).
   - **Constraints:**
     - `sale_order_id`: required, foreign key
     - `tracking_number`, `carrier`: required

8. **`canceled_order_items`**
   - **Tracks items from canceled orders, preserving historical pricing data.**
   - **Includes `sale_price` at the time of cancellation.**
   - **Constraints:**
     - `sale_order_id`: required, foreign key
     - `product_id`: required, foreign key
     - `canceled_quantity`: required, numeric

---

## **3️⃣ Model Implementations & Associations**

### **✅ Key Considerations in Models**
- **Explicit Foreign Key Handling:**
  - Used `belongs_to` with `foreign_key: "column_name"` where necessary.
- **Validation of Required Fields:**
  - Ensured `presence: true` for critical attributes.
- **Restrict Delete Dependencies:**
  - `dependent: :restrict_with_error` used to prevent accidental deletions.

### **✅ Model List**

1. **`User`**
   - **Associations:**
     - `has_many :purchase_orders`
     - `has_many :sale_orders`
   - **Validations:**
     - `email`: required, unique
     - `name`: required
     - `role`: required

2. **`Product`**
   - **Associations:**
     - `belongs_to :supplier, class_name: "User"`
   - **Validations:**
     - `product_sku`, `product_name`, `selling_price`: required

3. **`PurchaseOrder`**
   - **Associations:**
     - `belongs_to :user`
     - `has_many :inventory`
   - **Validations:**
     - `order_date`, `subtotal`, `total_order_cost`, `status`: required

4. **`SaleOrder`**
   - **Associations:**
     - `belongs_to :user`
     - `has_one :shipment`
     - `has_one :payment`
   - **Validations:**
     - `order_date`, `total_order_value`: required

5. **`Payment`**
   - **Associations:**
     - `belongs_to :sale_order`
   - **Validations:**
     - `amount`, `payment_method`, `status`: required

6. **`Shipment`**
   - **Associations:**
     - `belongs_to :sale_order`
   - **Validations:**
     - `tracking_number`, `carrier`, `status`: required

7. **`Inventory`**
   - **Associations:**
     - `belongs_to :product`
     - `belongs_to :purchase_order, optional: true`
     - `belongs_to :sale_order, optional: true`
   - **Validations:**
     - `purchase_cost`, `status`: required

8. **`CanceledOrderItem`**
   - **Associations:**
     - `belongs_to :sale_order`
     - `belongs_to :product`
   - **Validations:**
     - `canceled_quantity`, `sale_price_at_cancellation`: required

---

## **4️⃣ RSpec Testing Summary**

### **✅ Key Issues & Fixes**
1. **Unknown Validator `DateValidator` in Shipment Model** 🚨 → Removed incorrect validator.
2. **Missing Database Columns in PurchaseOrder Tests** 🚨 → Updated schema, ensured correct column names.
3. **User Email Uniqueness Validation Failure** 🚨 → Added `before do` block to create a valid user before testing uniqueness.

### **✅ Models Tested in RSpec**
- User
- Product
- PurchaseOrder
- SaleOrder
- Payment
- Shipment
- Inventory
- CanceledOrderItem

All models successfully pass validation, association, and custom logic tests. 🎉

---

## **5️⃣ Next Steps**
✅ Finalize integration testing with RSpec.
✅ Push latest updates to Git & deploy.
✅ Optimize queries for better performance.

🚀 **Database, models, and testing are now fully set up!** 🚀




