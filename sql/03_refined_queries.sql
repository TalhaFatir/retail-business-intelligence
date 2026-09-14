/*
===============================================================================
Retail Business Intelligence - Refined SQL Queries
===============================================================================
This file preserves the original project scripts separately and contains
recommended refinements for accuracy, reproducibility, and reusability.

Key improvements:
1. Count customer identifiers instead of summing them.
2. Keep month and year together in time-series analysis.
3. Use a <= 10 ranking boundary for Top 10 analysis.
4. Sort category contribution numerically.
5. Use a fixed dataset as-of date for historical age/recency analysis.
6. Handle missing birthdates explicitly.
7. Use consistent customer segmentation boundaries.
8. Use distinct customers/orders in product reporting.
9. Correct product performance thresholds.
10. Use CREATE OR ALTER VIEW and NULLIF() for rerunnable reporting logic.
===============================================================================
*/

/* ---------------------------------------------------------------------------
1. Customers by Country - corrected identifier aggregation
--------------------------------------------------------------------------- */
SELECT
    country,
    COUNT(DISTINCT customer_key) AS [Number of Customers]
FROM [dbo].[gold.dim_customers]
GROUP BY country
ORDER BY [Number of Customers] DESC;

/* ---------------------------------------------------------------------------
2. Monthly performance - retain the full month date instead of MONTH() alone
--------------------------------------------------------------------------- */
SELECT
    DATETRUNC(month, order_date) AS [Order Month],
    SUM(sales_amount) AS [Revenue],
    COUNT(DISTINCT customer_key) AS [Total Customers],
    SUM(quantity) AS [Total Quantity]
FROM [dbo].[gold.fact_sales]
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month, order_date)
ORDER BY [Order Month];

/* ---------------------------------------------------------------------------
3. Top 10 customers - ranking boundary aligned with the business question
--------------------------------------------------------------------------- */
WITH [Customer Revenue] AS
(
    SELECT
        c.customer_key,
        c.first_name,
        c.last_name,
        SUM(f.sales_amount) AS [Total Revenue]
    FROM [dbo].[gold.fact_sales] AS f
    LEFT JOIN [dbo].[gold.dim_customers] AS c
        ON c.customer_key = f.customer_key
    GROUP BY
        c.customer_key,
        c.first_name,
        c.last_name
),
[Ranked Customers] AS
(
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY [Total Revenue] DESC) AS [Revenue Rank]
    FROM [Customer Revenue]
)
SELECT *
FROM [Ranked Customers]
WHERE [Revenue Rank] <= 10
ORDER BY [Revenue Rank], customer_key;

/* ---------------------------------------------------------------------------
4. Category contribution - keep contribution numeric for sorting/calculation
--------------------------------------------------------------------------- */
WITH [Sales by Category] AS
(
    SELECT
        p.category AS [Category],
        SUM(f.sales_amount) AS [Category Sales]
    FROM [dbo].[gold.fact_sales] AS f
    LEFT JOIN [dbo].[gold.dim_products] AS p
        ON p.product_key = f.product_key
    GROUP BY p.category
)
SELECT
    [Category],
    [Category Sales],
    SUM([Category Sales]) OVER () AS [Overall Sales],
    CAST([Category Sales] AS decimal(18,4)) /
        NULLIF(SUM([Category Sales]) OVER (), 0) AS [Contribution Ratio],
    ROUND(
        100.0 * CAST([Category Sales] AS decimal(18,4)) /
        NULLIF(SUM([Category Sales]) OVER (), 0),
        2
    ) AS [Contribution Percent]
FROM [Sales by Category]
ORDER BY [Contribution Ratio] DESC;

/* ---------------------------------------------------------------------------
5. Refined customer reporting view
   - dataset max order date is used as a reproducible historical as-of date
   - NULL birthdates are classified as Unknown
   - Regular customer threshold consistently includes exactly $5,000
--------------------------------------------------------------------------- */
CREATE OR ALTER VIEW [dbo].[gold.customers_report_refined] AS
WITH [Analysis Date] AS
(
    SELECT MAX(order_date) AS [As Of Date]
    FROM [dbo].[gold.fact_sales]
    WHERE order_date IS NOT NULL
),
[Base Query] AS
(
    SELECT
        c.customer_key AS [Customer Key],
        c.customer_number AS [Customer Number],
        CONCAT(c.first_name, ' ', c.last_name) AS [Customer Name],
        c.birthdate AS [Birthdate],
        a.[As Of Date],
        f.order_date AS [Order Date],
        f.product_key AS [Product Key],
        f.order_number AS [Order Number],
        f.quantity AS [Quantity],
        f.sales_amount AS [Sales Amount]
    FROM [dbo].[gold.fact_sales] AS f
    LEFT JOIN [dbo].[gold.dim_customers] AS c
        ON c.customer_key = f.customer_key
    CROSS JOIN [Analysis Date] AS a
    WHERE f.order_date IS NOT NULL
),
[Customer Aggregation] AS
(
    SELECT
        [Customer Key],
        [Customer Number],
        [Customer Name],
        [Birthdate],
        [As Of Date],
        MIN([Order Date]) AS [First Order],
        MAX([Order Date]) AS [Last Order],
        DATEDIFF(month, MIN([Order Date]), MAX([Order Date])) AS [Order Timeframe],
        COUNT(DISTINCT [Product Key]) AS [Total Products],
        COUNT(DISTINCT [Order Number]) AS [Total Orders],
        SUM([Quantity]) AS [Total Quantity],
        SUM([Sales Amount]) AS [Total Sales]
    FROM [Base Query]
    GROUP BY
        [Customer Key],
        [Customer Number],
        [Customer Name],
        [Birthdate],
        [As Of Date]
)
SELECT
    [Customer Key],
    [Customer Number],
    [Customer Name],
    CASE
        WHEN [Birthdate] IS NULL THEN NULL
        ELSE DATEDIFF(year, [Birthdate], [As Of Date])
    END AS [Age],
    CASE
        WHEN [Birthdate] IS NULL THEN 'Unknown'
        WHEN DATEDIFF(year, [Birthdate], [As Of Date]) < 20 THEN 'Under 20'
        WHEN DATEDIFF(year, [Birthdate], [As Of Date]) BETWEEN 20 AND 29 THEN '20-29'
        WHEN DATEDIFF(year, [Birthdate], [As Of Date]) BETWEEN 30 AND 39 THEN '30-39'
        WHEN DATEDIFF(year, [Birthdate], [As Of Date]) BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and Above'
    END AS [Age Category],
    [First Order],
    [Last Order],
    DATEDIFF(month, [Last Order], [As Of Date]) AS [Months Since Last Order],
    [Order Timeframe],
    CASE
        WHEN [Order Timeframe] >= 12 AND [Total Sales] > 5000 THEN 'VIP Customers'
        WHEN [Order Timeframe] >= 12 AND [Total Sales] <= 5000 THEN 'Regular Customers'
        ELSE 'New Customers'
    END AS [Customer Category],
    [Total Products],
    [Total Orders],
    [Total Quantity],
    [Total Sales],
    CAST([Total Sales] AS decimal(18,2)) / NULLIF([Total Orders], 0) AS [Average Order Value],
    CASE
        WHEN [Order Timeframe] = 0 THEN CAST([Total Sales] AS decimal(18,2))
        ELSE CAST([Total Sales] AS decimal(18,2)) / NULLIF([Order Timeframe], 0)
    END AS [Average Monthly Revenue]
FROM [Customer Aggregation];

/* ---------------------------------------------------------------------------
6. Refined product reporting view
   - distinct customer and order counts
   - corrected High/Mid/Low thresholds
   - reproducible historical recency
--------------------------------------------------------------------------- */
CREATE OR ALTER VIEW [dbo].[gold.products_report_refined] AS
WITH [Analysis Date] AS
(
    SELECT MAX(order_date) AS [As Of Date]
    FROM [dbo].[gold.fact_sales]
    WHERE order_date IS NOT NULL
),
[Base Query] AS
(
    SELECT
        f.customer_key AS [Customer Key],
        f.order_number AS [Order Number],
        f.order_date AS [Order Date],
        p.product_key AS [Product Key],
        p.product_number AS [Product Number],
        p.product_name AS [Product Name],
        p.subcategory AS [Subcategory],
        p.category AS [Category],
        p.cost AS [Cost],
        f.quantity AS [Quantity],
        f.sales_amount AS [Sales Amount],
        a.[As Of Date]
    FROM [dbo].[gold.fact_sales] AS f
    LEFT JOIN [dbo].[gold.dim_products] AS p
        ON p.product_key = f.product_key
    CROSS JOIN [Analysis Date] AS a
    WHERE f.order_date IS NOT NULL
),
[Product Aggregation] AS
(
    SELECT
        [Product Key],
        [Product Number],
        [Product Name],
        [Subcategory],
        [Category],
        [Cost],
        [As Of Date],
        COUNT(DISTINCT [Customer Key]) AS [Total Customers],
        COUNT(DISTINCT [Order Number]) AS [Total Orders],
        MIN([Order Date]) AS [First Order],
        MAX([Order Date]) AS [Last Order],
        DATEDIFF(month, MIN([Order Date]), MAX([Order Date])) AS [Order Timeframe],
        SUM([Quantity]) AS [Total Quantity],
        SUM([Sales Amount]) AS [Total Sales],
        ROUND(AVG(CAST([Sales Amount] AS float) / NULLIF([Quantity], 0)), 1) AS [Average Selling Price]
    FROM [Base Query]
    GROUP BY
        [Product Key],
        [Product Number],
        [Product Name],
        [Subcategory],
        [Category],
        [Cost],
        [As Of Date]
)
SELECT
    [Product Key],
    [Product Number],
    [Product Name],
    [Subcategory],
    [Category],
    CASE
        WHEN [Total Sales] > 50000 THEN 'High Performing Product'
        WHEN [Total Sales] > 10000 THEN 'Mid Performing Product'
        ELSE 'Low Performing Product'
    END AS [Product Segmentation],
    [Cost],
    [Total Customers],
    [Total Orders],
    [First Order],
    [Last Order],
    DATEDIFF(month, [Last Order], [As Of Date]) AS [Months Since Last Order],
    [Order Timeframe],
    [Total Quantity],
    [Total Sales],
    [Average Selling Price],
    CAST([Total Sales] AS decimal(18,2)) / NULLIF([Total Orders], 0) AS [Average Order Revenue],
    CASE
        WHEN [Order Timeframe] = 0 THEN CAST([Total Sales] AS decimal(18,2))
        ELSE CAST([Total Sales] AS decimal(18,2)) / NULLIF([Order Timeframe], 0)
    END AS [Average Monthly Revenue]
FROM [Product Aggregation];
