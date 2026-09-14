/* Advanced Analytics Project: Changes Over Time Analysis 

1. Analyze Sales Performance Over Time. 

* Yearly Performance
* Monthly Performance
* Combined Yearly and Monthly Analysis */

-- Yearly Performance:
select 
	year(order_date) AS [Order Date],
	sum(sales_amount) [Revenue]
from [dbo].[gold.fact_sales]
where order_date is not null
group by year(order_date)
order by [Order Date];

-- Monthly Performance:
select 
	month(order_date) AS [Order Date],
	sum(sales_amount) [Revenue]
from [dbo].[gold.fact_sales]
where order_date is not null
group by month(order_date)
order by [Order Date];

-- Combined Yearly and Monthly Performance:
select
	datetrunc(month,order_date) AS [Order Date],
	sum(sales_amount) AS [Revenue],
	count(distinct customer_key) AS [Total Customers],
	sum(quantity) AS [Total Quantity]
from [dbo].[gold.fact_sales]
where order_date is not null
group by datetrunc(month,order_date)
order by [Order Date];

/* Advanced Analytics Project: Cumulative Analysis: */

/* 1. Calculate the total sales per month,the running total of sales over time,
and the moving average of the products' price */
select 
[Order Date],
[Total Sales],
sum([Total Sales]) over(order by [Order Date]) AS [Running Total of Sales],
avg([Average Price]) over(order by [Order Date]) AS [Moving Average of the Products' Price]
from
(
select
	datetrunc(month,order_date) AS [Order Date],
	sum(sales_amount) AS [Total Sales],
	avg(price) AS [Average Price]
from [dbo].[gold.fact_sales]
where order_date is not null 
group by datetrunc(month,order_date)
)t;
/* Advanced Analytics Project: Performance Analysis:

1. Analyze the yearly performance of products by
comparing each product's sales to both its average
sales performance and the previous year's sales. */
with [Yearly Product Sales] AS
(
select
	year(f.order_date) AS [Order Year],
	p.product_name AS [Product Name],
sum(f.sales_amount) [Current Sales]
from [dbo].[gold.fact_sales] as f
left join [dbo].[gold.dim_products] as p
on p.product_key = f.product_key
where (f.order_date) is not null 
group by 
	year(f.order_date),
	p.product_name
)
select
[Order Year],
[Product Name],
[Current Sales],
lag([Current Sales]) over(Partition by [Product Name] Order by [Order Year]) AS [Previous Year Sales],
[Current Sales] - lag([Current Sales]) over(Partition by [Product Name] Order by [Order Year]) AS [Difference from Previous Years],
Case 
	when [Current Sales] - lag([Current Sales]) over(Partition by [Product Name] Order by [Order Year]) > 0 Then 'Increase'
	when [Current Sales] - lag([Current Sales]) over(Partition by [Product Name] Order by [Order Year]) < 0 Then 'Decrease'
	Else 'No Change'
End AS [Change from Previous Year],
avg([Current Sales]) over(partition by [Product Name]) AS [Average Sales],
[Current Sales] - avg([Current Sales]) over(partition by [Product Name]) AS [Difference In Average],
Case
	when [Current Sales] - avg([Current Sales]) over(partition by [Product Name]) > 0 Then 'Above Average'
	when [Current Sales] - avg([Current Sales]) over(partition by [Product Name]) < 0 Then 'Below Average'
	Else 'Equal'
End AS [Performance Indicator of Each Products Each Year]
from [Yearly Product Sales]
order by [Product Name] ASC, [Order Year] ASC;

/* Advanced Analytics Project: Part-To-Whole Analysis:

1. Which categories contribute the most to overall sales */
with [Sales by Category] AS
(
select
p.category AS [Category],
sum(f.sales_Amount) AS [Total Sales by Category]
from [dbo].[gold.fact_sales] as f
left join [dbo].[gold.dim_products] as p
on p.product_key = f.product_key
group by p.category
)
select
[Category],
[Total Sales by Category],
sum([Total Sales by Category]) over() AS [Overall Sales],
concat(round((cast([Total Sales by Category] as float) / sum([Total Sales by Category]) over()) * 100,2),'%') AS [Contribution to Overall Sales]
from [Sales by Category]
order by [Contribution to Overall Sales] desc;

/* Advanced Analytics Project: Data Segmentation: 

1. Segment products into cost ranges and count how many products fall into
each segment. */
with [Cost Range Table] AS 
(
select
product_key AS [Product Key],
product_name AS [Product Name],
cost AS [Cost],
Case 
	when cost < 100 Then 'Below 100'
	when cost between 100 and 500 Then '100 - 500'
	when cost between 500 and 1000 Then '500-1000'
	Else 'Above 1000'
End AS [Cost Range]
from [dbo].[gold.dim_products]
)
select
[Cost Range],
count([Product Key]) [Number of Products]
from [Cost Range Table]
group by [Cost Range]
order by [Number of Products] desc;

/* 2. Group customers into three segments based on their
spending behavior: 
- VIP: Customers with at least 12 months of history 
and spending more than $5000.
- Regular: Customers with at least 12 months of 
history and spending $5000 or less. 
- New: Customers with a lifespan less than 12 months.
- Find the total number of customers by each group. 
*/
With [Order Timeframe Table] AS
(
select
c.customer_key AS [Customer Key],
min(f.order_date) AS [First Order Date],
max(f.order_date) AS [Last Order Date],
datediff(month, min(f.order_date),max(f.order_date)) AS [Order Timeframe],
sum(f.sales_amount) AS [Sales Amount]
from [dbo].[gold.fact_sales] AS f
left join [dbo].[gold.dim_customers] AS c
on c.customer_key = f.customer_key
group by c.customer_key 
)
select
[Customer Segmentation],
count([Customer Key]) AS [Number of Customers]
from
(
select
[Customer Key],
[First Order Date],
[Last Order Date],
[Sales Amount],
Case 
	When [Order Timeframe] >= 12 and [Sales Amount] > 5000 Then 'VIP Customers'
	When [Order Timeframe] >= 12 and [Sales Amount] <= 5000 Then 'Regular Customers'
	Else 'New Customers'
End AS [Customer Segmentation]
from [Order Timeframe Table]
)t
group by [Customer Segmentation]
order by [Number of Customers];

/* ==========================================================
Customer Report
=============================================================
Purpose: 
- This report consolidates key customer metrics and behaviors.

Highlights:
1. Gathers essential fields such as names, ages, and 
transaction details. 

2.Segment customers into categories (VIP, Regular, New) and
age groups. 

3.Aggregates customer-level metrics:
- Total orders
- Total sales
- Total quantity purchased
- Total Products
- Order Timeframe

4. Calculate valuable KPIs: 
 - Recency (Months since last order)
 - Average order value. 
 - Average monthly spend. 
 ============================================================
 */

 -- Base Query: Join all the columns needed for Analysis.
 CREATE VIEW [dbo].[gold.customers_report] AS 
 With [Base Query Table] AS
 (
 Select
	c.customer_key AS [Customer Key],
	c.customer_number AS [Customer Number],
	concat(c.first_name, ' ', c.last_name) AS [Customer Name],
	datediff(year, c.birthdate, getdate()) AS [Age],
	f.order_date AS [Order Date],
	f.product_key AS [Product Key],
	f.order_number AS [Order Number],
	f.quantity AS [Quantity],
	f.sales_amount AS [Sales Amount]
	From [dbo].[gold.fact_sales] as f
	left join [dbo].[gold.dim_customers] as c
	on c.customer_key = f.customer_key
	Where 
		f.order_date is not null 
)
-- Aggregation Query: Aggregate the needed columns from Base Query for analysis. 
, [Aggregation Query Table] AS
(
Select
	[Customer Key],
	[Customer Number],
	[Customer Name],
	[Age],
	max([Order Date]) AS [Last Order],
	datediff(month,min([Order Date]), max([Order Date])) AS [Order Timeframe],
	count(distinct [Product Key]) AS [Total Products],
	count(distinct [Order Number]) AS [Total Orders],
	sum([Quantity]) AS [Total Quantity],
	sum([Sales Amount]) AS [Total Sales]
From [Base Query Table]
Group By 
	[Customer Key],
	[Customer Name],
	[Customer Number],
	[Age]
)
Select
	[Customer Key],
	[Customer Name],
	[Customer Number],
Case 
	When [Age] < 20 Then 'Under 20'
	When [Age] Between 20 and 29 Then '20-29'
	When [Age] Between 30 and 39 Then '30-39'
	When [Age] Between 40 and 49 Then '40-49'
	Else '50 and Above'
End AS [Age Category],
	[Last Order],
	datediff(month,[Last Order],getdate()) AS [Months Since last order],
	[Order Timeframe],
Case 
	When [Order Timeframe] >= 12 AND [Total Sales] > 5000 Then 'VIP Customers'
	When [Order Timeframe] >= 12 AND [Total Sales] < 5000 Then 'Regular Customers'
	Else 'New'
End AS [Customer Category],
	[Total Products],
	[Total Orders],
	[Total Quantity],
	[Total Sales],
Case
	When [Total Sales] = 0 Then 0
	Else [Total Sales] / [Total Orders]
End AS [Average Order Value],
Case
	When [Order Timeframe] = 0 Then [Total Sales]
	Else [Total Sales] / [Order Timeframe]
End [Average Monthly Revenue]
From [Aggregation Query Table];

/* Advanced Analytics Project: Build Product Report:

================================================================
Product Report
================================================================
Purpose: This report consolidates key product metrics and 
behaviours. 

Highlights: 
1. Gather essential fields such as product name, category,
subcategory, and cost.
2. Segments products by revenue to identify High-Performers,
Mid-Range, or Low-Performers. 
3.Aggregate product-level metrics:
- Total orders
- Total Sales
- Total Quantity Sold
- Total customers (unique)
- Lifespan (in months)
4. Calculate valuable KPIs:
- Recency (Months since last sale)
- Average order revenue (AOR)
- Average monthly revenue
===============================================================
*/
-- Base Query:
CREATE VIEW [dbo].[gold.products_report] AS
With [Base Query Table] AS
(
Select
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
	f.sales_amount AS [Sales Amount]
From [dbo].[gold.fact_sales] as f
left join [dbo].[gold.dim_products] as p
on p.product_key = f.product_key 
)
, [Aggregation Table] AS
(
Select 
	[Product Key],
	[Product Number],
	[Product Name],
	[Subcategory],
	[Category],
	[Cost],
	count([Customer Key]) AS [Total Customers],
	count([Order Number]) AS [Total Orders],
	max([Order Date]) AS [Last Order],
	datediff(month,min([Order Date]),max([Order Date]))AS [Order Timeframe],
	sum([Quantity]) AS [Total Quantity],
	sum([Sales Amount]) AS [Total Sales],
	round(avg(cast([Sales Amount] as float) / NULLIF ([Quantity], 0)),1) AS [Average Selling Price]
From [Base Query Table]
Group By 
	[Product Key],
	[Product Number],
	[Product Name],
	[Subcategory],
	[Category],
	[Cost]
)
Select
	[Product Key],
	[Product Number],
	[Product Name],
	[Subcategory],
	[Category],
Case 
	When [Total Sales] > 50000 Then 'High Performing Product'
	When [Total Sales] <= 10000 Then 'Mid - Performing Product'
	Else 'Low Performing Product'
End AS [Product Segmentation],
	[Cost],
	[Total Customers],
	[Total Orders],
	[Last Order],
	datediff(month,[Last Order],getdate()) AS [Months Since Last Order],
	[Order Timeframe],
	[Total Quantity],
	[Total Sales],
	[Average Selling Price],
Case
	When [Total Orders] = 0 Then 0
	Else [Total Sales] / [Total Orders] 
End AS [Average Order Revenue],
Case
	When [Order Timeframe] = 0 Then 0
	Else [Total Sales] / [Order Timeframe]
End AS [Average Monthly Revenue]
From [Aggregation Table];