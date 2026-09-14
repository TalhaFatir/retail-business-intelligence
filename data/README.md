# Raw Data

This folder contains the three source CSV tables used in the project.

| File | Rows | Description |
|---|---:|---|
| `dim_customers.csv` | 18,484 | Customer dimension with customer identifiers, names, country, gender, marital status, birthdate, and create date. |
| `dim_products.csv` | 295 | Product dimension with product identifiers, product names, category/subcategory, cost, product line, and start date. |
| `fact_sales.csv` | 60,398 | Sales fact table with order number, customer/product keys, order/shipping/due dates, sales amount, quantity, and price. |

## Data model

The project follows a star-schema style analytical model:

- `fact_sales[customer_key]` joins to `dim_customers[customer_key]`
- `fact_sales[product_key]` joins to `dim_products[product_key]`
- Power BI adds a dedicated date table for time-intelligence calculations.

## Dataset coverage

- Sales date range: **2010-12-29 to 2014-01-28**
- Total sales: **$29,356,250**
- Distinct orders: **27,659**
- Total quantity: **60,423**
- Customers: **18,484**
- Products: **295**

The raw files are retained without analytical transformations so the SQL and Power BI steps remain reproducible.