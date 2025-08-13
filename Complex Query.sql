--1. Top 5 Agents by Commission in the Last 12 Months
WITH agent_commissions AS (
  SELECT 
    c.listing_agent_id AS agent_id,
    SUM(c.total_commission_amount) FILTER (WHERE c.created_at >= NOW() - INTERVAL '1 year') AS total_commission,
    COUNT(*) FILTER (WHERE c.created_at >= NOW() - INTERVAL '1 year')        AS transactions_count
  FROM Commission c
  GROUP BY c.listing_agent_id
),
agent_rank AS (
  SELECT 
    ac.*,
    e.first_name,
    e.last_name,
    ROW_NUMBER() OVER (ORDER BY ac.total_commission DESC) AS rank
  FROM agent_commissions ac
  JOIN Employee e ON e.employee_id = ac.agent_id
)
SELECT 
  rank,
  agent_id,
  first_name,
  last_name,
  total_commission,
  transactions_count
FROM agent_rank
WHERE rank <= 5;

--2. Average Days on Market by Property Type
SELECT
  pt.type_name,
  ROUND(AVG((COALESCE(p.date_sold, CURRENT_DATE) - p.date_listed))::numeric, 2) AS avg_days_on_market,
  COUNT(*) AS properties_count
FROM Property p
JOIN PropertyType pt ON pt.type_id = p.property_type_id
GROUP BY pt.type_name
ORDER BY avg_days_on_market DESC;

--3. Lead Conversion Funnel by Source
SELECT
  lead_source,
  COUNT(*) AS total_leads,
  SUM(CASE WHEN lead_status = 'contacted'  THEN 1 ELSE 0 END) AS contacted,
  SUM(CASE WHEN lead_status = 'qualified' THEN 1 ELSE 0 END) AS qualified,
  SUM(CASE WHEN lead_status = 'converted' THEN 1 ELSE 0 END) AS converted,
  ROUND(
    100.0 * SUM(CASE WHEN lead_status = 'converted' THEN 1 ELSE 0 END)
    / NULLIF(COUNT(*), 0),
    2
  ) AS conversion_rate_pct
FROM ClientLead
WHERE created_at >= DATE_TRUNC('year', CURRENT_DATE)
GROUP BY lead_source
ORDER BY conversion_rate_pct DESC;

--4. Properties with Both Pool and Garage Features
SELECT
  p.property_id,
  p.address,
  p.city,
  p.state,
  STRING_AGG(pf.feature_name, ', ' ORDER BY pf.feature_name) AS features
FROM Property p
JOIN PropertyFeature pf ON pf.property_id = p.property_id
GROUP BY p.property_id, p.address, p.city, p.state
HAVING 
  COUNT(DISTINCT CASE WHEN pf.feature_name ILIKE '%Pool%'   THEN 1 END) > 0
  AND COUNT(DISTINCT CASE WHEN pf.feature_name ILIKE '%Garage%' THEN 1 END) > 0;

--5. Office Sales Closing Performance & Ranking
WITH sales AS (
  SELECT
    t.transaction_id,
    p.listing_office_id AS office_id,
    (t.closing_date - t.offer_date) AS days_to_close
  FROM "Transaction" t
  JOIN Property p ON p.property_id = t.property_id
  WHERE t.transaction_type = 'sale'
    AND t.closing_date IS NOT NULL
),
office_perf AS (
  SELECT
    office_id,
    AVG(days_to_close) AS avg_days_to_close,
    COUNT(*)        AS total_sales
  FROM sales
  GROUP BY office_id
),
ranked AS (
  SELECT
    op.*,
    o.office_name,
    RANK() OVER (ORDER BY op.avg_days_to_close) AS closing_rank
  FROM office_perf op
  JOIN Office o ON o.office_id = op.office_id
)
SELECT
  closing_rank,
  office_id,
  office_name,
  avg_days_to_close,
  total_sales
FROM ranked
ORDER BY closing_rank;

--6. Monthly Sale vs. Rental Revenue & MoM Growth
WITH sale_revenue AS (
  SELECT
    DATE_TRUNC('month', closing_date) AS month,
    SUM(transaction_amount)           AS sale_revenue
  FROM "Transaction"
  WHERE transaction_type = 'sale'
    AND closing_date >= CURRENT_DATE - INTERVAL '1 year'
  GROUP BY month
),
rental_income AS (
  SELECT
    DATE_TRUNC('month', pr.payment_date) AS month,
    SUM(pr.amount)                       AS rental_income
  FROM PaymentRecord pr
  JOIN Lease l ON l.lease_id = pr.lease_id
  WHERE pr.payment_type = 'rent'
    AND payment_date >= CURRENT_DATE - INTERVAL '1 year'
  GROUP BY month
),
combined AS (
  SELECT
    COALESCE(s.month, r.month) AS month,
    COALESCE(s.sale_revenue, 0)   AS sale_revenue,
    COALESCE(r.rental_income, 0)  AS rental_income
  FROM sale_revenue s
  FULL JOIN rental_income r USING (month)
)
SELECT
  month,
  sale_revenue,
  rental_income,
  (sale_revenue + rental_income)                                     AS total_revenue,
  LAG(sale_revenue + rental_income) OVER (ORDER BY month)            AS prev_month_revenue,
  ROUND(
    100.0 * ((sale_revenue + rental_income)
      - LAG(sale_revenue + rental_income) OVER (ORDER BY month))
    / NULLIF(LAG(sale_revenue + rental_income) OVER (ORDER BY month),0),
    2
  ) AS mom_growth_pct
FROM combined
ORDER BY month;

--7. Clients Who Are Both Buyers and Sellers
SELECT
  c.client_id,
  c.full_name,
  STRING_AGG(DISTINCT cr.role_type::text, ', ') AS roles
FROM Client c
JOIN ClientRole cr 
  ON cr.client_id = c.client_id 
  AND cr.is_active
  AND cr.role_type IN ('buyer','seller')
GROUP BY c.client_id, c.full_name
HAVING COUNT(DISTINCT cr.role_type) = 2;

--8. Marketing Campaign ROI & Revenue per Lead
WITH campaign_revenue AS (
  SELECT
    mc.campaign_id,
    SUM(t.transaction_amount) AS total_revenue
  FROM MarketingCampaign mc
  LEFT JOIN "Transaction" t
    ON t.property_id = mc.property_id
   AND t.closing_date BETWEEN mc.start_date AND COALESCE(mc.end_date, CURRENT_DATE)
  WHERE mc.start_date >= CURRENT_DATE - INTERVAL '1 year'
  GROUP BY mc.campaign_id
)
SELECT
  mc.campaign_id,
  mc.campaign_name,
  mc.actual_cost,
  mc.leads_generated,
  COALESCE(cr.total_revenue, 0)      AS total_revenue,
  ROUND(
    COALESCE(cr.total_revenue, 0) / NULLIF(mc.actual_cost, 0),
    2
  ) AS roi_multiplier,
  ROUND(
    COALESCE(cr.total_revenue, 0) / NULLIF(mc.leads_generated, 0),
    2
  ) AS revenue_per_lead
FROM MarketingCampaign mc
LEFT JOIN campaign_revenue cr USING (campaign_id)
ORDER BY roi_multiplier DESC NULLS LAST;