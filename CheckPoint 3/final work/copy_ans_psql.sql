-- 为枚举类型创建自定义类型
CREATE TYPE employment_status_type AS ENUM ('active', 'inactive', 'terminated');
CREATE TYPE client_type_enum AS ENUM ('individual', 'company');
CREATE TYPE role_type_enum AS ENUM ('buyer', 'seller', 'renter', 'landlord');
CREATE TYPE property_status_enum AS ENUM ('active', 'pending', 'sold', 'rented', 'withdrawn');
CREATE TYPE media_type_enum AS ENUM ('photo', 'video', 'document', 'floor_plan');
CREATE TYPE appointment_type_enum AS ENUM ('showing', 'open_house', 'virtual_tour', 'inspection');
CREATE TYPE appointment_status_enum AS ENUM ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show');
CREATE TYPE transaction_type_enum AS ENUM ('sale', 'rental');
CREATE TYPE transaction_status_enum AS ENUM ('pending', 'in_escrow', 'completed', 'cancelled');
CREATE TYPE payout_status_enum AS ENUM ('pending', 'approved', 'paid');
CREATE TYPE lease_status_enum AS ENUM ('active', 'expired', 'terminated', 'renewed');
CREATE TYPE payment_type_enum AS ENUM ('rent', 'deposit', 'late_fee', 'utility', 'maintenance', 'other');
CREATE TYPE payment_method_enum AS ENUM ('check', 'cash', 'bank_transfer', 'online', 'money_order');
CREATE TYPE payment_status_enum AS ENUM ('completed', 'pending', 'failed', 'refunded');
CREATE TYPE campaign_type_enum AS ENUM ('online', 'print', 'social_media', 'open_house', 'email', 'direct_mail');
CREATE TYPE campaign_status_enum AS ENUM ('planned', 'active', 'paused', 'completed', 'cancelled');
CREATE TYPE lead_source_enum AS ENUM ('website', 'referral', 'walk_in', 'phone_call', 'social_media', 'advertisement', 'other');
CREATE TYPE interest_type_enum AS ENUM ('buying', 'selling', 'renting', 'leasing');
CREATE TYPE lead_status_enum AS ENUM ('new', 'contacted', 'qualified', 'converted', 'closed_lost');
CREATE TYPE document_type_enum AS ENUM ('contract', 'disclosure', 'inspection_report', 'appraisal', 'title_report', 'insurance', 'other');
CREATE TYPE feature_type_enum AS ENUM ('amenity', 'appliance', 'structural', 'outdoor', 'parking');

-- 1. Office: Physical office locations and management
DROP TABLE IF EXISTS Office CASCADE;
CREATE TABLE Office (
    office_id SERIAL PRIMARY KEY,
    office_code VARCHAR(10) NOT NULL UNIQUE,
    office_name VARCHAR(100) NOT NULL,
    address VARCHAR(200) NOT NULL,
    city VARCHAR(50) NOT NULL,
    state CHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    manager_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_office_location ON Office (city, state);
CREATE INDEX idx_office_manager ON Office (manager_id);

-- 2. Employee: Staff members and agents
DROP TABLE IF EXISTS Employee CASCADE;
CREATE TABLE Employee (
    employee_id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) NOT NULL UNIQUE,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    job_title VARCHAR(50) NOT NULL,
    employment_status employment_status_type NOT NULL DEFAULT 'active',
    office_id INTEGER NOT NULL,
    manager_id INTEGER,
    hire_date DATE NOT NULL,
    commission_rate DECIMAL(4,2) DEFAULT 3.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (office_id) REFERENCES Office(office_id),
    FOREIGN KEY (manager_id) REFERENCES Employee(employee_id),
    CONSTRAINT chk_commission_rate CHECK (commission_rate >= 0 AND commission_rate <= 15)
);

CREATE INDEX idx_employee_name ON Employee (last_name, first_name);
CREATE INDEX idx_employee_office ON Employee (office_id);

-- Update foreign key in Office table after Employee table is created
ALTER TABLE Office ADD CONSTRAINT fk_office_manager FOREIGN KEY (manager_id) REFERENCES Employee(employee_id);

-- 3. Client: Individual and corporate clients
DROP TABLE IF EXISTS Client CASCADE;
CREATE TABLE Client (
    client_id SERIAL PRIMARY KEY,
    client_type client_type_enum NOT NULL DEFAULT 'individual',
    full_name VARCHAR(150) NOT NULL,
    company_name VARCHAR(150),
    email VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    address VARCHAR(200),
    city VARCHAR(50),
    state CHAR(2),
    zip_code VARCHAR(10),
    assigned_agent_id INTEGER,
    registration_date DATE NOT NULL DEFAULT CURRENT_DATE,
    is_vip BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (assigned_agent_id) REFERENCES Employee(employee_id),
    CONSTRAINT chk_company_client CHECK (
        (client_type = 'company' AND company_name IS NOT NULL) 
        OR client_type = 'individual'
    )
);

CREATE INDEX idx_client_name ON Client (full_name);
CREATE INDEX idx_client_agent ON Client (assigned_agent_id);

-- 4. ClientRole: Many-to-many relationship for client roles
DROP TABLE IF EXISTS ClientRole CASCADE;
CREATE TABLE ClientRole (
    client_role_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL,
    role_type role_type_enum NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES Client(client_id) ON DELETE CASCADE,
    UNIQUE (client_id, role_type)
);

CREATE INDEX idx_role_type ON ClientRole (role_type);

-- 5. PropertyType: Property type definitions and characteristics
DROP TABLE IF EXISTS PropertyType CASCADE;
CREATE TABLE PropertyType (
    type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(200),
    typical_features JSONB,
    is_residential BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_residential ON PropertyType (is_residential);

-- 6. Property: Real estate properties
DROP TABLE IF EXISTS Property CASCADE;
CREATE TABLE Property (
    property_id SERIAL PRIMARY KEY,
    mls_number VARCHAR(50) UNIQUE,
    property_type_id INTEGER NOT NULL,
    listing_office_id INTEGER NOT NULL,
    listing_agent_id INTEGER NOT NULL,
    address VARCHAR(200) NOT NULL,
    city VARCHAR(50) NOT NULL,
    state CHAR(2) NOT NULL,
    zip_code VARCHAR(10) NOT NULL,
    list_price DECIMAL(12,2) NOT NULL,
    square_footage INTEGER,
    bedrooms SMALLINT,
    bathrooms DECIMAL(3,1),
    year_built INTEGER,
    lot_size DECIMAL(8,2),
    current_status property_status_enum NOT NULL DEFAULT 'active',
    date_listed DATE NOT NULL DEFAULT CURRENT_DATE,
    date_sold DATE,
    sold_price DECIMAL(12,2),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_type_id) REFERENCES PropertyType(type_id),
    FOREIGN KEY (listing_office_id) REFERENCES Office(office_id),
    FOREIGN KEY (listing_agent_id) REFERENCES Employee(employee_id),
    CONSTRAINT chk_list_price CHECK (list_price > 0),
    CONSTRAINT chk_sold_price CHECK (sold_price IS NULL OR sold_price > 0)
);

CREATE INDEX idx_property_location ON Property (city, state, zip_code);
CREATE INDEX idx_property_price ON Property (list_price);
CREATE INDEX idx_property_status ON Property (current_status);
CREATE INDEX idx_property_agent ON Property (listing_agent_id);
CREATE INDEX idx_property_type ON Property (property_type_id);

-- 创建触发器更新updated_at
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_property_timestamp
BEFORE UPDATE ON Property
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

-- 7. PropertyFeature: Property-specific features and amenities
DROP TABLE IF EXISTS PropertyFeature CASCADE;
CREATE TABLE PropertyFeature (
    feature_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    feature_type feature_type_enum NOT NULL,
    feature_name VARCHAR(100) NOT NULL,
    feature_value VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES Property(property_id) ON DELETE CASCADE
);

CREATE INDEX idx_feature_property ON PropertyFeature (property_id);
CREATE INDEX idx_feature_type ON PropertyFeature (feature_type);

-- 8. PropertyMedia: Media files for properties
DROP TABLE IF EXISTS PropertyMedia CASCADE;
CREATE TABLE PropertyMedia (
    media_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    media_type media_type_enum NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    title VARCHAR(100),
    description VARCHAR(200),
    is_primary BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 0,
    uploaded_by INTEGER NOT NULL,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES Property(property_id) ON DELETE CASCADE,
    FOREIGN KEY (uploaded_by) REFERENCES Employee(employee_id)
);

CREATE INDEX idx_media_property ON PropertyMedia (property_id);
CREATE INDEX idx_media_primary ON PropertyMedia (property_id, is_primary);

-- 9. Appointment: Property viewing appointments
DROP TABLE IF EXISTS Appointment CASCADE;
CREATE TABLE Appointment (
    appointment_id SERIAL PRIMARY KEY,
    agent_id INTEGER NOT NULL,
    client_id INTEGER NOT NULL,
    property_id INTEGER NOT NULL,
    scheduled_datetime TIMESTAMP NOT NULL,
    duration_minutes INTEGER DEFAULT 60,
    appointment_type appointment_type_enum DEFAULT 'showing',
    status appointment_status_enum DEFAULT 'scheduled',
    notes TEXT,
    feedback TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER NOT NULL,
    FOREIGN KEY (agent_id) REFERENCES Employee(employee_id),
    FOREIGN KEY (client_id) REFERENCES Client(client_id),
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (created_by) REFERENCES Employee(employee_id),
    CONSTRAINT chk_duration CHECK (duration_minutes > 0 AND duration_minutes <= 480)
);

CREATE INDEX idx_appointment_datetime ON Appointment (scheduled_datetime);
CREATE INDEX idx_appointment_agent ON Appointment (agent_id);
CREATE INDEX idx_appointment_client ON Appointment (client_id);
CREATE INDEX idx_appointment_property ON Appointment (property_id);

-- 10. Transaction: Sales and rental transactions
DROP TABLE IF EXISTS "Transaction" CASCADE;
CREATE TABLE "Transaction" (
    transaction_id SERIAL PRIMARY KEY,
    transaction_code VARCHAR(30) NOT NULL UNIQUE,
    property_id INTEGER NOT NULL,
    listing_agent_id INTEGER NOT NULL,
    selling_agent_id INTEGER,
    buyer_id INTEGER,
    seller_id INTEGER,
    renter_id INTEGER,
    landlord_id INTEGER,
    transaction_type transaction_type_enum NOT NULL,
    status transaction_status_enum DEFAULT 'pending',
    offer_date DATE NOT NULL,
    offer_amount DECIMAL(12,2) NOT NULL,
    accepted_date DATE,
    transaction_amount DECIMAL(12,2) NOT NULL,
    closing_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (listing_agent_id) REFERENCES Employee(employee_id),
    FOREIGN KEY (selling_agent_id) REFERENCES Employee(employee_id),
    FOREIGN KEY (buyer_id) REFERENCES Client(client_id),
    FOREIGN KEY (seller_id) REFERENCES Client(client_id),
    FOREIGN KEY (renter_id) REFERENCES Client(client_id),
    FOREIGN KEY (landlord_id) REFERENCES Client(client_id),
    CONSTRAINT chk_transaction_parties CHECK (
        (transaction_type = 'sale' AND buyer_id IS NOT NULL AND seller_id IS NOT NULL AND renter_id IS NULL AND landlord_id IS NULL) OR
        (transaction_type = 'rental' AND renter_id IS NOT NULL AND landlord_id IS NOT NULL AND buyer_id IS NULL AND seller_id IS NULL)
    ),
    CONSTRAINT chk_amounts CHECK (transaction_amount > 0 AND offer_amount > 0)
);

CREATE INDEX idx_transaction_property ON "Transaction" (property_id);
CREATE INDEX idx_transaction_status ON "Transaction" (status);
CREATE INDEX idx_transaction_agents ON "Transaction" (listing_agent_id, selling_agent_id);
CREATE INDEX idx_transaction_type ON "Transaction" (transaction_type);

-- 11. Commission: Agent commission tracking
DROP TABLE IF EXISTS Commission CASCADE;
CREATE TABLE Commission (
    commission_id SERIAL PRIMARY KEY,
    transaction_id INTEGER NOT NULL UNIQUE,
    total_commission_amount DECIMAL(10,2) NOT NULL,
    listing_agent_id INTEGER NOT NULL,
    listing_agent_amount DECIMAL(10,2) NOT NULL,
    selling_agent_id INTEGER,
    selling_agent_amount DECIMAL(10,2),
    office_split_percentage DECIMAL(4,2) DEFAULT 50.00,
    payout_status payout_status_enum NOT NULL DEFAULT 'pending',
    payout_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (transaction_id) REFERENCES "Transaction"(transaction_id),
    FOREIGN KEY (listing_agent_id) REFERENCES Employee(employee_id),
    FOREIGN KEY (selling_agent_id) REFERENCES Employee(employee_id),
    CONSTRAINT chk_commission_amounts CHECK (total_commission_amount > 0)
);

CREATE INDEX idx_commission_status ON Commission (payout_status);
CREATE INDEX idx_commission_agents ON Commission (listing_agent_id, selling_agent_id);

-- 12. Lease: Rental agreements
DROP TABLE IF EXISTS Lease CASCADE;
CREATE TABLE Lease (
    lease_id SERIAL PRIMARY KEY,
    lease_number VARCHAR(30) NOT NULL UNIQUE,
    property_id INTEGER NOT NULL,
    transaction_id INTEGER NOT NULL,
    renter_id INTEGER NOT NULL,
    landlord_id INTEGER NOT NULL,
    lease_start_date DATE NOT NULL,
    lease_end_date DATE NOT NULL,
    monthly_rent DECIMAL(8,2) NOT NULL,
    security_deposit DECIMAL(8,2) NOT NULL,
    lease_status lease_status_enum NOT NULL DEFAULT 'active',
    lease_terms TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER NOT NULL,
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (transaction_id) REFERENCES "Transaction"(transaction_id),
    FOREIGN KEY (renter_id) REFERENCES Client(client_id),
    FOREIGN KEY (landlord_id) REFERENCES Client(client_id),
    FOREIGN KEY (created_by) REFERENCES Employee(employee_id),
    CONSTRAINT chk_lease_dates CHECK (lease_end_date > lease_start_date),
    CONSTRAINT chk_lease_amounts CHECK (monthly_rent > 0 AND security_deposit >= 0)
);

CREATE INDEX idx_lease_property ON Lease (property_id);
CREATE INDEX idx_lease_renter ON Lease (renter_id);
CREATE INDEX idx_lease_status ON Lease (lease_status);

-- 13. PaymentRecord: Rental payment tracking
DROP TABLE IF EXISTS PaymentRecord CASCADE;
CREATE TABLE PaymentRecord (
    payment_id SERIAL PRIMARY KEY,
    lease_id INTEGER NOT NULL,
    payment_date DATE NOT NULL,
    amount DECIMAL(8,2) NOT NULL,
    payment_type payment_type_enum NOT NULL,
    payment_method payment_method_enum NOT NULL,
    reference_number VARCHAR(50),
    status payment_status_enum DEFAULT 'completed',
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (lease_id) REFERENCES Lease(lease_id)
);

CREATE INDEX idx_payment_lease ON PaymentRecord (lease_id);
CREATE INDEX idx_payment_date ON PaymentRecord (payment_date);
CREATE INDEX idx_payment_status ON PaymentRecord (status);

-- 14. MarketingCampaign: Property marketing campaigns
DROP TABLE IF EXISTS MarketingCampaign CASCADE;
CREATE TABLE MarketingCampaign (
    campaign_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    campaign_name VARCHAR(100) NOT NULL,
    campaign_type campaign_type_enum NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    budget DECIMAL(8,2),
    actual_cost DECIMAL(8,2),
    leads_generated INTEGER DEFAULT 0,
    status campaign_status_enum DEFAULT 'planned',
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (created_by) REFERENCES Employee(employee_id)
);

CREATE INDEX idx_campaign_property ON MarketingCampaign (property_id);
CREATE INDEX idx_campaign_dates ON MarketingCampaign (start_date, end_date);
CREATE INDEX idx_campaign_status ON MarketingCampaign (status);

-- 15. ClientLead: Potential client inquiries and leads
DROP TABLE IF EXISTS ClientLead CASCADE;
CREATE TABLE ClientLead (
    lead_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    lead_source lead_source_enum NOT NULL,
    property_id INTEGER,
    interest_type interest_type_enum NOT NULL,
    budget_min DECIMAL(12,2),
    budget_max DECIMAL(12,2),
    preferred_location VARCHAR(100),
    assigned_agent_id INTEGER,
    lead_status lead_status_enum DEFAULT 'new',
    notes TEXT,
    follow_up_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (assigned_agent_id) REFERENCES Employee(employee_id)
);

CREATE INDEX idx_lead_agent ON ClientLead (assigned_agent_id);
CREATE INDEX idx_lead_status ON ClientLead (lead_status);
CREATE INDEX idx_lead_source ON ClientLead (lead_source);
CREATE INDEX idx_lead_follow_up ON ClientLead (follow_up_date);

-- 16. Document: Transaction and legal documents
DROP TABLE IF EXISTS Document CASCADE;
CREATE TABLE Document (
    document_id SERIAL PRIMARY KEY,
    transaction_id INTEGER,
    property_id INTEGER,
    document_type document_type_enum NOT NULL,
    document_name VARCHAR(200) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size_bytes INTEGER,
    uploaded_by INTEGER NOT NULL,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_required BOOLEAN DEFAULT FALSE,
    expiry_date DATE,
    FOREIGN KEY (transaction_id) REFERENCES "Transaction"(transaction_id),
    FOREIGN KEY (property_id) REFERENCES Property(property_id),
    FOREIGN KEY (uploaded_by) REFERENCES Employee(employee_id)
);

CREATE INDEX idx_document_transaction ON Document (transaction_id);
CREATE INDEX idx_document_property ON Document (property_id);
CREATE INDEX idx_document_type ON Document (document_type);