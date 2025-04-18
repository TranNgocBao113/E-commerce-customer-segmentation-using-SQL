---CONTEXT:
/* Company: E-commerce platform "ShopX" that specializes in selling electronics, fashion, and household items online. 
			The company has been in operation for 5 years and has a large customer base but lacks a clear customer segmentation 
			strategy. ShopX is looking to optimize its marketing strategies, improve customer experience, and increase revenue 
			through customer data analysis.

	Current Issue: The company is facing challenges in optimizing its marketing strategy and customer care, especially targeting 
			the right customer segments. The current advertising campaigns are not performing well because customers are not being 
			segmented effectively. Therefore, a more scientific approach to customer segmentation based on shopping behavior and data is needed.
*/
-------------------------------------------------------------------------------------------------------------------------------------------------
---  PROJECT: Execute Customer Segmentation at ShopX to enhance the marketing performance 

/* Description: This project focuses on customer segmentation using SQL to analyze purchasing behavior. 
				By applying RFM (Recency, Frequency, Monetary) analysis alongside demographic attributes 
				such as age, gender, and region, customers are grouped into meaningful segments. 
				These insights help the business understand its customer base better and optimize marketing efforts 
				by targeting the right audience more effectively. The entire analysis is performed with SQL, 
				and the results can be directly used for visualization in Power BI.
*/

---1. Define objective:

---2. Analysis method: RFM (Recency, Frequency, Monetary) + demographic analysis

---3. Query:
CREATE OR ALTER PROCEDURE sp_RFM
	@analysis_date DATE
AS
BEGIN
    -- Drop table if exists
    IF OBJECT_ID(N'dbo.RFM', N'U') IS NOT NULL  
		DROP TABLE [dbo].[RFM]; 
	
	CREATE TABLE RFM (
		customer_id int, 
		total_RFM_score varchar(255), 
		name varchar(255), 
		gender varchar(255), 
		age int,
		region varchar(255), 
		signup_date date,
		recency int,
		frequency int,
		monetary decimal,
		recency_label int,
		frequency_label int,
		monetary_label int);

    -- Recalculate total_amount if null
    WITH recalculated_amount AS (
        SELECT 
            order_id,
            SUM(unit_price * quantity) AS computed_total
        FROM [e-commerce].dbo.order_detail
        GROUP BY order_id
    )
    UPDATE o
    SET o.total_amount = r.computed_total
    FROM [e-commerce].dbo.orders o
    JOIN recalculated_amount r ON o.order_id = r.order_id
    WHERE o.total_amount IS NULL;

    --- Create CTEs
    WITH 
    cleaned_customer AS (
        SELECT DISTINCT customer_id, name, gender, age, region, signup_date 
        FROM [e-commerce].dbo.customer
        WHERE customer_id IS NOT NULL AND signup_date IS NOT NULL
    ),
    cleaned_order_details AS (
        SELECT DISTINCT order_detail_id, order_id, product_id, quantity, unit_price 
        FROM [e-commerce].dbo.order_detail
        WHERE order_detail_id IS NOT NULL
    ),
    cleaned_orders AS (
        SELECT DISTINCT order_id, customer_id, order_date, total_amount 
        FROM [e-commerce].dbo.orders
        WHERE order_id IS NOT NULL
    ),
    full_order_table AS (
        SELECT o.customer_id, d.order_id, d.product_id, d.quantity, o.total_amount, o.order_date
        FROM cleaned_order_details AS d
        JOIN cleaned_orders AS o ON d.order_id = o.order_id
    ),
    after_analysis_date_orders AS (
        SELECT customer_id, MAX(order_date) AS last_order_after_analysis_date
        FROM cleaned_orders
        WHERE order_date >= @analysis_date
        GROUP BY customer_id
    ),
    RFM_table AS (
        SELECT 
            c.customer_id, 
            CASE 
                WHEN a.last_order_after_analysis_date IS NULL THEN 9999
                ELSE ABS(DATEDIFF(DAY, a.last_order_after_analysis_date, @analysis_date))
            END AS Recency,
            COUNT(f.order_id) AS Frequency, 
            ROUND(AVG(f.total_amount), 2) AS Monetary
        FROM cleaned_customer c
        LEFT JOIN full_order_table f ON c.customer_id = f.customer_id
        LEFT JOIN after_analysis_date_orders a ON c.customer_id = a.customer_id
        GROUP BY c.customer_id, a.last_order_after_analysis_date
    ),
    RFM_percentile_WO_recency AS (
        SELECT 
            customer_id,
            Recency,
            Frequency,
            Monetary,
            ROUND(PERCENT_RANK() OVER(ORDER BY Frequency ASC), 2) AS percent_rank_frequency,
            ROUND(PERCENT_RANK() OVER(ORDER BY Monetary ASC), 2) AS percent_rank_monetary
        FROM RFM_table
    ),
	RFM_w_recency AS (
		SELECT 
            customer_id,
            Recency,
            Frequency,
            Monetary,
            ROUND(PERCENT_RANK() OVER(ORDER BY Recency ASC), 2) AS percent_rank_recency
        FROM RFM_table
		WHERE Recency != 9999
	),
	RFM_percentile AS (
		SELECT
			wo.customer_id,
			wo.Recency,
			wo.Monetary,
			wo.Frequency,
			wo.percent_rank_frequency,
			wo.percent_rank_monetary,
			CASE
				WHEN r.percent_rank_recency IS NULL THEN 9999
				ELSE r.percent_rank_recency
			END AS percent_rank_recency
		FROM RFM_percentile_WO_recency AS wo
		LEFT JOIN RFM_w_recency AS r
			ON wo.customer_id = r.customer_id
	),
	---Label for each Recency, Frequency, Monetary
    RFM_Label AS (
        SELECT 
            customer_id,
            Recency,
            Frequency,
            Monetary,
            CASE	
				WHEN percent_rank_recency = 9999 THEN 4 ---Used to order before analysis date but does not order anymore
                WHEN percent_rank_recency < 0.25 THEN 1 
                WHEN percent_rank_recency > 0.75 and percent_rank_recency <= 1 THEN 3
                WHEN percent_rank_recency <= 0.75 AND percent_rank_recency >= 0.25 THEN 2
            END AS recency_label,
            CASE	
                WHEN percent_rank_frequency < 0.25 THEN 1
                WHEN percent_rank_frequency > 0.75 THEN 3
                WHEN percent_rank_frequency <= 0.75 AND percent_rank_frequency >= 0.25 THEN 2
            END AS frequency_label,
            CASE	
                WHEN percent_rank_monetary < 0.25 THEN 1
                WHEN percent_rank_monetary > 0.75 THEN 3
                WHEN percent_rank_monetary <= 0.75 AND percent_rank_monetary >= 0.25 THEN 2
            END AS monetary_label
        FROM RFM_percentile
    ),
	---Label the RFM group for each customer
	final_RFM as (
		SELECT 
			customer_id, 
			Recency,
            Frequency,
            Monetary,
			CONCAT(recency_label, frequency_label, monetary_label) AS total_RFM_score
		FROM RFM_Label
	)

	INSERT INTO RFM
    SELECT 
		r.customer_id as customer_id, 
		r.total_RFM_score as total_RFM_score, 
		c.name as name, 
		c.gender as gender, 
		c.age as age, 
		c.region as region, 
		c.signup_date as signup_date,
		r.Recency,
		r.Frequency,
		r.Monetary,
		l.recency_label,
		l.frequency_label,
		l.monetary_label
    FROM final_RFM AS r
    JOIN cleaned_customer AS c ON r.customer_id = c.customer_id
	JOIN RFM_Label as l ON r.customer_id = l.customer_id
END;
GO

-- Call procedure
EXEC sp_RFM @analysis_date = '2023-01-01';


