--# 
--# This file demo_insertion.py is built for demo the insertion of data into the database
--# for demo purposes to show interaction between the database and Metabase Dashboard
--# it is not used in the final version of the ETL pipeline
--#

-- This is the SQL code for demo insertion of data into the database
    
-- Query01: Insert foundation data

-- Insert Office, Employee, PropertyType, and Property
-- This sets up the basic data structure

-- Insert Office
INSERT INTO Office (office_code, office_name, address, city, state, zip_code, phone, email)
VALUES ('DEMO01', 'Dream Homes Demo Office', '123 Demo Street', 'New York', 'NY', '10001', '(212) 555-DEMO', 'demo@dreamhomes.com');

-- Insert PropertyType
INSERT INTO PropertyType (type_name, description, is_residential)
VALUES ('Demo Condo', 'Demonstration condominium unit', TRUE);

-- Insert Employee (triggers auto-generation of employee_code)
INSERT INTO Employee (
    first_name, last_name, email, phone, job_title, 
    office_id, hire_date, commission_rate
) 
VALUES (
    'Demo', 'Agent', 'demo.agent@dreamhomes.com', '(212) 555-0001', 
    'Senior Agent', 1, CURRENT_DATE, 3.50
);

-- Insert Client
INSERT INTO Client (
    client_type, full_name, email, phone, assigned_agent_id
)
VALUES (
    'individual', 'Demo Buyer', 'demo.buyer@email.com', '(917) 555-0002', 1
),
(
    'individual', 'Demo Seller', 'demo.seller@email.com', '(646) 555-0003', 1
);

-- Insert ClientRoles
INSERT INTO ClientRole (client_id, role_type) VALUES (1, 'buyer'), (2, 'seller');

-- Insert Demo Property
INSERT INTO Property (
    mls_number, property_type_id, listing_office_id, listing_agent_id,
    address, city, state, zip_code, list_price, square_footage,
    bedrooms, bathrooms, current_status, date_listed, description
) 
VALUES (
    'DEMO-12345', 1, 1, 1,
    '456 Demo Avenue Unit 5A', 'New York', 'NY', '10002', 
    850000.00, 1200, 2, 2.0, 'active', CURRENT_DATE,
    'Beautiful demo property for Metabase testing'
);

-- Check what was inserted
SELECT 'Data Insertion Complete - Check Metabase Dashboard!' as status;

------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
--Alternative Query02: 
-- Demonstrate real-time updates by changing data
-- Run these one at a time and watch Metabase dashboards update

-- Step 1: Add a marketing campaign
INSERT INTO MarketingCampaign (
    property_id, campaign_name, campaign_type, start_date, 
    budget, actual_cost, leads_generated, status, created_by
)
VALUES (
    1, 'Demo Property Social Media Campaign', 'social_media', CURRENT_DATE - INTERVAL '30 days',
    5000.00, 4750.00, 25, 'completed', 1
);

-- Step 2: Add property features  
INSERT INTO PropertyFeature (property_id, feature_type, feature_name, feature_value)
VALUES 
(1, 'amenity', 'Gym', 'Building fitness center'),
(1, 'amenity', 'Doorman', '24/7 concierge service'),
(1, 'appliance', 'Dishwasher', 'Stainless steel');

-- Step 3: Update commission payout status (shows real-time change)
UPDATE Commission 
SET payout_status = 'paid', payout_date = CURRENT_DATE
WHERE transaction_id = 1;

-- Step 4: Add appointment history
INSERT INTO Appointment (
    agent_id, client_id, property_id, scheduled_datetime,
    appointment_type, status, notes, feedback, created_by
)
VALUES (
    1, 1, 1, CURRENT_DATE - INTERVAL '20 days',
    'showing', 'completed', 'Client very interested in the unit',
    'Loved the kitchen and city views', 1
);

-- Final status check
SELECT 
    'Real-time updates complete!' as message,
    COUNT(pf.feature_id) as total_features,
    COUNT(mc.campaign_id) as total_campaigns,
    COUNT(a.appointment_id) as total_appointments,
    c.payout_status as commission_status
FROM Property p
LEFT JOIN PropertyFeature pf ON p.property_id = pf.property_id
LEFT JOIN MarketingCampaign mc ON p.property_id = mc.property_id  
LEFT JOIN Appointment a ON p.property_id = a.property_id
LEFT JOIN "Transaction" t ON p.property_id = t.property_id
LEFT JOIN Commission c ON t.transaction_id = c.transaction_id
WHERE p.property_id = 1
GROUP BY c.payout_status;