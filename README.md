# 📌 **Rails Database Migration & Setup Summary**

## **1️⃣ Overview**
This document outlines all the steps taken to set up and migrate the database for the Rails 8.0.1 application, including Devise authentication, database structure, and table relationships.

---

## **2️⃣ Database Tables Created & Adjustments**
### **✅ Tables Created:**
1. `users`  
   - **Added Devise authentication.**
   - **Role-based authorization:** Roles include `admin`, `customer`, and `supplier`.
   - **Wholesale customers:** Introduced `discount_rate` for wholesale customers.
   - **Updated column `user_type` → `role` for clarity.**

2. `products`  
   - **New columns:**
     - `discount_limited_stock` to control how many products can be sold at a discounted rate.
     - `maximum_discount` to define the highest possible discount.
   - **Barcode is now optional.**

3. `inventory`
   - **Each row represents an individual product unit.**
   - Tracks **purchase cost and sale cost per item**.
   - **Status-based tracking:** `Available`, `Reserved`, `Sold`, `Lost`, `Damaged`, `Scrap`, `In Transit`.
   - **Updated to store `purchase_order_id` and `sale_order_id` instead of separate order items tables.**

4. `purchase_orders`
   - **Handles supplier orders.**
   - **Backorders are supported**.
   - **Purchase orders split** when partial shipments occur.

5. `sale_orders`
   - **Handles customer orders.**
   - **Linked to `payments` and `shipments` tables**.
   - **Expected & actual delivery dates removed** (handled by `shipments`).

6. `payments`
   - **Tracks customer payments**.
   - **New `status` column** to track `Pending`, `Completed`, `Refunded`, etc.
   - **Initially created without `sale_order_id`, then updated in a separate migration**.

7. `shipments`
   - **Tracks shipments for both sales and purchases.**
   - **New columns:** `last_update` (timestamp) & `status` (e.g., Pending, Shipped, Delivered).

8. `canceled_order_items`
   - **Tracks items from canceled orders, preserving historical pricing data.**
   - **Includes `sale_price` at the time of cancellation.**

---

## **3️⃣ Migration Issues & Fixes**
### **🚨 Key Issues Encountered & Solutions**

1. **Unknown Key `:unique` in Migrations** ❌ → Removed and added `index: { unique: true }` instead.
2. **Unknown Key `:foreign_key` in Migrations** ❌ → Used `t.references ... foreign_key: true` instead.
3. **Table Creation Order Issues** 🚨
   - Some tables referenced foreign keys before their parent tables were created.
   - **Fix:** Renamed migration files to enforce correct sequence.
4. **Datatype Mismatch in Foreign Keys** 🚨
   - `sale_orders.id` was `VARCHAR(50)`, but references were defaulting to `bigint`.
   - **Fix:** Explicitly set `t.string` for foreign keys referencing `sale_orders`.
5. **Payments Table Referencing Sale Orders Before They Existed** 🚨
   - **Fix:** First created `payments` without `sale_order_id`, then added it in a separate migration.

---

## **4️⃣ Next Steps**
✅ **Verify Database Schema**
```sh
rails db:migrate:status
```
✅ **Test Basic Queries in Rails Console**
```ruby
rails console
User.count
Product.count
SaleOrder.count
```
✅ **Push to Git**
```sh
git add .
git commit -m "Completed database migration and Devise setup"
git push origin <branch-name>
```
✅ **Deploy to Heroku** (if applicable)
```sh
heroku run rails db:migrate
```

---

### **🚀 Summary**
- **Migrations completed successfully.** 🎉
- **Database is structured efficiently for tracking individual items and historical pricing.**
- **Devise authentication with role-based authorization implemented.**
- **Ready for testing and further development.**

**👉 Let me know if any additional documentation is needed! 🚀**

