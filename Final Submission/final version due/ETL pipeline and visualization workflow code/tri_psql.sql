CREATE OR REPLACE FUNCTION trg_update_property_status_after_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE Property 
        SET current_status = CASE 
            WHEN NEW.transaction_type = 'sale' THEN 'sold'::property_status_enum
            WHEN NEW.transaction_type = 'rental' THEN 'rented'::property_status_enum
        END,
        date_sold = NEW.closing_date,
        sold_price = NEW.transaction_amount
        WHERE property_id = NEW.property_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_property_status_after_transaction
AFTER INSERT ON "Transaction"
FOR EACH ROW
EXECUTE FUNCTION trg_update_property_status_after_transaction();

CREATE OR REPLACE FUNCTION trg_generate_employee_code()
RETURNS TRIGGER AS $$
DECLARE 
    office_code VARCHAR(10);
    next_number INT;
BEGIN
    -- Get office code
    SELECT o.office_code INTO office_code
    FROM Office o WHERE o.office_id = NEW.office_id;
    
    -- Get next number
    SELECT COALESCE(MAX(CAST(SUBSTRING(e.employee_code FROM LENGTH(office_code) + 2) AS INTEGER)), 0) + 1
    INTO next_number
    FROM Employee e
    WHERE e.employee_code LIKE office_code || '-%';
    
    -- Set employee code
    NEW.employee_code = office_code || '-' || LPAD(next_number::TEXT, 4, '0');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_employee_code
BEFORE INSERT ON Employee
FOR EACH ROW
EXECUTE FUNCTION trg_generate_employee_code();

CREATE OR REPLACE FUNCTION trg_create_commission_record()
RETURNS TRIGGER AS $$
DECLARE
    listing_rate DECIMAL(4,2);
    selling_rate DECIMAL(4,2);
    total_commission DECIMAL(10,2);
    commission_exists INT DEFAULT 0;
BEGIN
    -- Check if commission record already exists
    SELECT COUNT(*) INTO commission_exists FROM Commission WHERE transaction_id = NEW.transaction_id;
    
    IF NEW.status = 'completed' AND OLD.status != 'completed' AND commission_exists = 0 THEN
        -- Get agent commission rates
        SELECT commission_rate INTO listing_rate
        FROM Employee WHERE employee_id = NEW.listing_agent_id;
        
        IF NEW.selling_agent_id IS NOT NULL THEN
            SELECT commission_rate INTO selling_rate
            FROM Employee WHERE employee_id = NEW.selling_agent_id;
        ELSE
            selling_rate := 0;
        END IF;
        
        -- Calculate total commission (assume 6% of transaction amount)
        total_commission := NEW.transaction_amount * 0.06;
        
        -- Create commission record
        INSERT INTO Commission (
            transaction_id, 
            total_commission_amount,
            listing_agent_id,
            listing_agent_amount,
            selling_agent_id,
            selling_agent_amount
        ) VALUES (
            NEW.transaction_id,
            total_commission,
            NEW.listing_agent_id,
            total_commission * listing_rate / 100,
            NEW.selling_agent_id,
            CASE WHEN NEW.selling_agent_id IS NOT NULL THEN total_commission * selling_rate / 100 ELSE 0 END
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_commission_record
AFTER UPDATE ON "Transaction"
FOR EACH ROW
EXECUTE FUNCTION trg_create_commission_record();

CREATE OR REPLACE FUNCTION trg_convert_lead_to_client()
RETURNS TRIGGER AS $$
DECLARE
    client_exists INT DEFAULT 0;
BEGIN
    IF NEW.lead_status = 'converted' AND OLD.lead_status != 'converted' THEN
        -- Check if client already exists with same email
        SELECT COUNT(*) INTO client_exists 
        FROM Client 
        WHERE email = NEW.email;
        
        IF client_exists = 0 AND NEW.email IS NOT NULL THEN
            -- Create new client record
            INSERT INTO Client (
                client_type,
                full_name,
                email,
                phone,
                assigned_agent_id,
                notes
            ) VALUES (
                'individual',
                NEW.first_name || ' ' || NEW.last_name,
                NEW.email,
                NEW.phone,
                NEW.assigned_agent_id,
                'Converted from lead ID: ' || NEW.lead_id
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_convert_lead_to_client
AFTER UPDATE ON ClientLead
FOR EACH ROW
EXECUTE FUNCTION trg_convert_lead_to_client();