-- Dream Homes Real Estate Database - 12 Essential Client Queries

-- Question 1: What features and amenities can I expect at different price points?
WITH price_ranges AS (
    SELECT property_id, list_price,
           CASE 
               WHEN list_price < 300000 THEN 'Under $300K'
               WHEN list_price < 500000 THEN '$300K-500K'
               WHEN list_price < 750000 THEN '$500K-750K'
               ELSE 'Over $750K'
           END as price_range
    FROM Property
    WHERE current_status IN ('active', 'sold') AND list_price > 0
)
SELECT pr.price_range,
       pf.feature_type,
       pf.feature_name,
       COUNT(*) as feature_count,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY pr.price_range), 2) as percentage_in_range
FROM price_ranges pr
JOIN PropertyFeature pf ON pr.property_id = pf.property_id
GROUP BY pr.price_range, pf.feature_type, pf.feature_name
HAVING COUNT(*) >= 5
ORDER BY pr.price_range, percentage_in_range DESC;

-- Question 2: Which marketing strategies work best and what do they cost?
SELECT mc.campaign_type,
       COUNT(*) as total_campaigns,
       ROUND(AVG(mc.budget), 0) as avg_budget,
       ROUND(AVG(mc.actual_cost), 0) as avg_actual_cost,
       ROUND(AVG(mc.leads_generated), 0) as avg_leads_generated,
       ROUND(AVG(mc.leads_generated / NULLIF(mc.actual_cost, 0)), 4) as leads_per_dollar,
       COUNT(CASE WHEN p.current_status = 'sold' THEN 1 END) as properties_sold,
       ROUND(COUNT(CASE WHEN p.current_status = 'sold' THEN 1 END) * 100.0 / COUNT(*), 2) as success_rate
FROM MarketingCampaign mc
JOIN Property p ON mc.property_id = p.property_id
WHERE mc.status = 'completed'
  AND mc.start_date >= CURRENT_DATE - INTERVAL '18 months'
GROUP BY mc.campaign_type
HAVING COUNT(*) >= 5
ORDER BY success_rate DESC, leads_per_dollar DESC;

-- Question 3: How much extra rent can I charge for specific amenities?
SELECT pf.feature_type, pf.feature_name,
       COUNT(*) as properties_with_feature,
       ROUND(AVG(l.monthly_rent), 0) as avg_rent_with_feature,
       ROUND(AVG(l.monthly_rent) - (
           SELECT AVG(l2.monthly_rent) 
           FROM Lease l2 
           JOIN Property p2 ON l2.property_id = p2.property_id 
           WHERE l2.lease_status = 'active'
       ), 0) as rent_premium,
       ROUND(AVG(l.monthly_rent / NULLIF(p.square_footage, 0)), 2) as rent_per_sqft
FROM PropertyFeature pf
JOIN Property p ON pf.property_id = p.property_id
JOIN Lease l ON p.property_id = l.property_id
WHERE l.lease_status = 'active'
  AND p.current_status = 'rented'
GROUP BY pf.feature_type, pf.feature_name
HAVING COUNT(*) >= 3
ORDER BY rent_premium DESC;

-- Question 4: Who are the best rental agents in the area?
SELECT e.first_name || ' ' || e.last_name as agent_name,
       e.phone, e.email,
       o.office_name,
       COUNT(DISTINCT p.property_id) as rental_properties_managed,
       COUNT(DISTINCT l.lease_id) as active_leases,
       ROUND(AVG(l.monthly_rent), 0) as avg_rental_price,
       STRING_AGG(DISTINCT CONCAT(p.bedrooms, '-bed'), ', ') as property_types_managed,
       COUNT(DISTINCT a.appointment_id) as total_appointments
FROM Employee e
JOIN Office o ON e.office_id = o.office_id
JOIN Property p ON e.employee_id = p.listing_agent_id
JOIN Lease l ON p.property_id = l.property_id
LEFT JOIN Appointment a ON e.employee_id = a.agent_id
WHERE l.lease_status = 'active'
  AND e.employment_status = 'active'
  AND p.current_status = 'rented'
GROUP BY e.employee_id, e.first_name, e.last_name, e.phone, e.email, o.office_name
HAVING COUNT(DISTINCT l.lease_id) >= 3
ORDER BY rental_properties_managed DESC;

-- Question 5: How can I evaluate if a tenant will be reliable?
SELECT c.client_id, c.full_name, c.email, c.registration_date,
       COUNT(DISTINCT l.lease_id) as total_leases,
       COUNT(DISTINCT CASE WHEN l.lease_status = 'active' THEN l.lease_id END) as current_leases,
       ROUND(AVG(l.monthly_rent), 0) as avg_rental_amount,
       MIN(l.lease_start_date) as first_lease_date,
       MAX(l.lease_end_date) as latest_lease_end,
       COUNT(pr.payment_id) as total_payments_made,
       COUNT(CASE WHEN pr.status = 'completed' THEN 1 END) as successful_payments,
       ROUND(COUNT(CASE WHEN pr.status = 'completed' THEN 1 END) * 100.0 / NULLIF(COUNT(pr.payment_id), 0), 2) as payment_success_rate
FROM Client c
JOIN ClientRole cr ON c.client_id = cr.client_id
JOIN Lease l ON c.client_id = l.renter_id
LEFT JOIN PaymentRecord pr ON l.lease_id = pr.lease_id
WHERE cr.role_type = 'renter'
  AND cr.is_active = TRUE
GROUP BY c.client_id, c.full_name, c.email, c.registration_date
HAVING COUNT(DISTINCT l.lease_id) >= 1
ORDER BY payment_success_rate DESC, total_leases DESC;

-- Question 6: Which property management companies perform the best?
SELECT o.office_name, o.city as office_location,
       COUNT(DISTINCT e.employee_id) as total_staff,
       COUNT(DISTINCT p.property_id) as properties_managed,
       COUNT(DISTINCT c.client_id) as clients_served,
       ROUND(AVG(l.monthly_rent), 0) as avg_rental_price,
       COUNT(DISTINCT a.appointment_id) as appointments_handled,
       COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as successful_transactions,
       ROUND(COUNT(CASE WHEN t.status = 'completed' THEN 1 END) * 100.0 / NULLIF(COUNT(t.transaction_id), 0), 2) as transaction_success_rate
FROM Office o
JOIN Employee e ON o.office_id = e.office_id
LEFT JOIN Property p ON e.employee_id = p.listing_agent_id
LEFT JOIN Client c ON e.employee_id = c.assigned_agent_id
LEFT JOIN Lease l ON p.property_id = l.property_id
LEFT JOIN Appointment a ON e.employee_id = a.agent_id
LEFT JOIN "Transaction" t ON p.property_id = t.property_id
WHERE e.employment_status = 'active'
  AND o.is_active = TRUE
GROUP BY o.office_id, o.office_name, o.city
HAVING COUNT(DISTINCT p.property_id) >= 3
ORDER BY transaction_success_rate DESC, properties_managed DESC;

-- Question 7: When is the best time of year to sell my house?
SELECT EXTRACT(QUARTER FROM t.closing_date) as quarter,
       CASE EXTRACT(QUARTER FROM t.closing_date)
           WHEN 1 THEN 'Q1 (Jan-Mar)'
           WHEN 2 THEN 'Q2 (Apr-Jun)'
           WHEN 3 THEN 'Q3 (Jul-Sep)'
           WHEN 4 THEN 'Q4 (Oct-Dec)'
       END as season,
       COUNT(*) as total_sales,
       ROUND(AVG(t.transaction_amount), 0) as avg_sale_price,
       ROUND(AVG(t.closing_date - p.date_listed), 0) as avg_days_on_market,
       ROUND(AVG(t.transaction_amount / p.list_price * 100), 2) as avg_sale_to_list_ratio,
       COUNT(CASE WHEN t.transaction_amount > p.list_price THEN 1 END) as sales_above_asking
FROM "Transaction" t
JOIN Property p ON t.property_id = p.property_id
WHERE t.transaction_type = 'sale'
  AND t.status = 'completed'
  AND t.closing_date >= CURRENT_DATE - INTERVAL '24 months'
GROUP BY EXTRACT(QUARTER FROM t.closing_date)
ORDER BY quarter;

-- Question 8: What should I know about lease terms and rental contracts?
WITH lease_terms AS (
    SELECT l.lease_id,
           (l.lease_end_date - l.lease_start_date) as lease_duration_days,
           l.monthly_rent,
           l.security_deposit,
           CASE 
               WHEN (l.lease_end_date - l.lease_start_date) <= 180 THEN 'Short-term (≤6 months)'
               WHEN (l.lease_end_date - l.lease_start_date) <= 365 THEN 'Standard (6-12 months)'
               ELSE 'Long-term (>12 months)'
           END as lease_term_category
    FROM Lease l
    WHERE l.lease_status IN ('active', 'expired')
)
SELECT lease_term_category,
       COUNT(*) as lease_count,
       ROUND(AVG(lease_duration_days), 0) as avg_duration_days,
       ROUND(AVG(monthly_rent), 0) as avg_monthly_rent,
       ROUND(AVG(security_deposit), 0) as avg_security_deposit,
       ROUND(AVG(security_deposit / monthly_rent), 1) as deposit_to_rent_ratio,
       ROUND(MIN(monthly_rent), 0) as min_rent,
       ROUND(MAX(monthly_rent), 0) as max_rent
FROM lease_terms
GROUP BY lease_term_category
ORDER BY avg_duration_days;

-- Question 9: When is the real estate market most active?
WITH monthly_activity AS (
    SELECT EXTRACT(MONTH FROM t.offer_date) as month,
           EXTRACT(QUARTER FROM t.offer_date) as quarter,
           COUNT(*) as total_transactions,
           COUNT(CASE WHEN t.transaction_type = 'sale' THEN 1 END) as sales,
           COUNT(CASE WHEN t.transaction_type = 'rental' THEN 1 END) as rentals,
           AVG(t.transaction_amount) as avg_transaction_value,
           COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as completed_deals
    FROM "Transaction" t
    WHERE t.offer_date >= CURRENT_DATE - INTERVAL '24 months'
    GROUP BY EXTRACT(MONTH FROM t.offer_date), EXTRACT(QUARTER FROM t.offer_date)
)
SELECT month,
       CASE month
           WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
           WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
           WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
           WHEN 10 THEN 'October' WHEN 11 THEN 'November' WHEN 12 THEN 'December'
       END as month_name,
       quarter,
       total_transactions,
       sales,
       rentals,
       ROUND(avg_transaction_value, 0) as avg_transaction_value,
       ROUND(completed_deals * 100.0 / total_transactions, 2) as completion_rate,
       CASE 
           WHEN total_transactions >= (SELECT AVG(total_transactions) * 1.2 FROM monthly_activity) THEN 'High Activity'
           WHEN total_transactions >= (SELECT AVG(total_transactions) * 0.8 FROM monthly_activity) THEN 'Normal Activity'
           ELSE 'Low Activity'
       END as activity_level
FROM monthly_activity
ORDER BY month;

-- Question 10: What house size gives me the best value for money?
WITH size_categories AS (
    SELECT property_id, square_footage, list_price, bedrooms,
           CASE 
               WHEN square_footage < 1000 THEN 'Small (<1000 sqft)'
               WHEN square_footage < 1500 THEN 'Medium (1000-1500 sqft)'
               WHEN square_footage < 2000 THEN 'Large (1500-2000 sqft)'
               ELSE 'Extra Large (>2000 sqft)'
           END as size_category
    FROM Property
    WHERE square_footage IS NOT NULL AND list_price > 0
)
SELECT sc.size_category,
       COUNT(*) as property_count,
       ROUND(AVG(sc.list_price), 0) as avg_list_price,
       ROUND(AVG(sc.list_price / sc.square_footage), 2) as avg_price_per_sqft,
       ROUND(MIN(sc.list_price / sc.square_footage), 2) as min_price_per_sqft,
       ROUND(MAX(sc.list_price / sc.square_footage), 2) as max_price_per_sqft,
       COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as sold_count,
       ROUND(AVG(t.closing_date - p.date_listed), 0) as avg_days_to_sell,
       ROUND(COUNT(CASE WHEN t.status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2) as sell_through_rate
FROM size_categories sc
JOIN Property p ON sc.property_id = p.property_id
LEFT JOIN "Transaction" t ON p.property_id = t.property_id AND t.transaction_type = 'sale'
GROUP BY sc.size_category
ORDER BY avg_price_per_sqft ASC;

-- Question 11: How does neighborhood safety affect home prices?
WITH neighborhood_metrics AS (
    SELECT p.city, p.zip_code,
           COUNT(*) as total_properties,
           AVG(p.list_price) as avg_property_value,
           COUNT(pf.feature_id) as security_features_count,
           COUNT(CASE WHEN pf.feature_name ILIKE '%security%' OR pf.feature_name ILIKE '%alarm%' OR pf.feature_name ILIKE '%gate%' THEN 1 END) as security_properties
    FROM Property p
    LEFT JOIN PropertyFeature pf ON p.property_id = pf.property_id
    WHERE p.current_status IN ('active', 'sold')
      AND p.list_price > 0
    GROUP BY p.city, p.zip_code
    HAVING COUNT(*) >= 5
)
SELECT city, zip_code,
       total_properties,
       ROUND(avg_property_value, 0) as avg_property_value,
       security_properties,
       ROUND(security_properties * 100.0 / total_properties, 2) as security_feature_percentage,
       CASE 
           WHEN security_properties * 100.0 / total_properties >= 50 THEN 'High Security Area'
           WHEN security_properties * 100.0 / total_properties >= 25 THEN 'Medium Security Area'
           ELSE 'Standard Area'
       END as security_rating,
       ROUND(avg_property_value / (SELECT AVG(avg_property_value) FROM neighborhood_metrics) * 100, 2) as relative_value_index
FROM neighborhood_metrics
ORDER BY security_feature_percentage DESC, avg_property_value DESC;

-- Question 12: Which property management company should I choose?
WITH management_performance AS (
    SELECT o.office_id, o.office_name, o.city,
           COUNT(DISTINCT e.employee_id) as total_agents,
           COUNT(DISTINCT p.property_id) as properties_managed,
           COUNT(DISTINCT l.lease_id) as active_leases,
           COUNT(DISTINCT c.client_id) as clients_served,
           AVG(l.monthly_rent) as avg_rent_managed,
           COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as successful_transactions,
           COUNT(DISTINCT a.appointment_id) as appointments_handled,
           AVG(CASE WHEN t.closing_date IS NOT NULL THEN t.closing_date - p.date_listed END) as avg_transaction_time
    FROM Office o
    JOIN Employee e ON o.office_id = e.office_id
    LEFT JOIN Property p ON e.employee_id = p.listing_agent_id
    LEFT JOIN Lease l ON p.property_id = l.property_id AND l.lease_status = 'active'
    LEFT JOIN Client c ON e.employee_id = c.assigned_agent_id
    LEFT JOIN "Transaction" t ON p.property_id = t.property_id
    LEFT JOIN Appointment a ON e.employee_id = a.agent_id
    WHERE e.employment_status = 'active'
      AND o.is_active = TRUE
    GROUP BY o.office_id, o.office_name, o.city
    HAVING COUNT(DISTINCT p.property_id) >= 5
)
SELECT office_name, city,
       total_agents,
       properties_managed,
       active_leases,
       clients_served,
       ROUND(avg_rent_managed, 0) as avg_rent_managed,
       successful_transactions,
       appointments_handled,
       ROUND(avg_transaction_time, 0) as avg_days_to_complete,
       ROUND(properties_managed / NULLIF(total_agents, 0), 1) as properties_per_agent,
       ROUND(successful_transactions * 100.0 / NULLIF(properties_managed, 0), 2) as success_rate,
       CASE 
           WHEN successful_transactions * 100.0 / NULLIF(properties_managed, 0) >= 80 THEN 'Excellent Performance'
           WHEN successful_transactions * 100.0 / NULLIF(properties_managed, 0) >= 60 THEN 'Good Performance'
           ELSE 'Average Performance'
       END as performance_rating
FROM management_performance
ORDER BY success_rate DESC, properties_per_agent DESC;