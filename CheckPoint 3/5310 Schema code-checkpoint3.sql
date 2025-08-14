-- =============================================================================
-- DREAM HOMES NYC DATABASE SCHEMA - FINAL SUBMISSION
-- Project Checkpoint 3 - Database Schema Design
-- Course: APAN 5310 - SQL and Relational Databases
-- Team: Yuxuan Chen, Yishan Liu, Xianghui Meng, Steven Huo
-- Date: [Current Date]
-- Version: 2.0 (Final)
-- 
-- SUBMISSION CONTENTS:
-- 1. Complete PostgreSQL DDL for Dream Homes NYC real estate database
-- 2. 27 normalized tables with comprehensive business logic
-- 3. Advanced triggers, constraints, and automation
-- 4. Performance optimization with 25+ indexes
-- 5. Business intelligence views and analytics
-- 6. Role-based security and access control
-- 
-- NOTE: This submission is for instructor feedback purposes.
-- The schema addresses all business requirements from project documentation.
-- =============================================================================

-- Create database and configure settings
CREATE DATABASE dream_homes_nyc_v2;
\c dream_homes_nyc_v2;

SET timezone = 'America/New_York';
SET default_text_search_config = 'pg_catalog.english';

-- =============================================================================
-- CONFIGURATION AND LOOKUP TABLES
-- =============================================================================

-- Commission rate configuration table
CREATE TABLE commission_rates (
    rate_id SERIAL PRIMARY KEY,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('Sale', 'Rental')),
    property_type VARCHAR(50) NOT NULL,
    min_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    max_amount DECIMAL(12,2),
    commission_rate DECIMAL(5,4) NOT NULL CHECK (commission_rate >= 0 AND commission_rate <= 1),
    office_split_rate DECIMAL(5,4) NOT NULL DEFAULT 0.5 CHECK (office_split_rate >= 0 AND office_split_rate <= 1),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (max_amount IS NULL OR max_amount > min_amount),
    CHECK (expiry_date IS NULL OR expiry_date > effective_date)
);

-- Property status transition rules
CREATE TABLE property_status_transitions (
    transition_id SERIAL PRIMARY KEY,
    from_status VARCHAR(20) NOT NULL,
    to_status VARCHAR(20) NOT NULL,
    is_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    requires_approval BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(from_status, to_status)
);

-- =============================================================================
-- CORE ORGANIZATIONAL TABLES
-- =============================================================================

-- Office locations (removed circular reference)
CREATE TABLE offices (
    office_id SERIAL PRIMARY KEY,
    office_name VARCHAR(100) NOT NULL,
    office_code VARCHAR(10) NOT NULL UNIQUE,
    address_line1 VARCHAR(200) NOT NULL,
    address_line2 VARCHAR(200),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL CHECK (state IN ('NY', 'NJ', 'CT')),
    zip_code VARCHAR(10) NOT NULL CHECK (zip_code ~ '^\d{5}(-\d{4})?$'),
    phone VARCHAR(20) NOT NULL CHECK (phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    email VARCHAR(100) NOT NULL UNIQUE CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    fax VARCHAR(20) CHECK (fax ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    website VARCHAR(200),
    established_date DATE,
    office_size_sqft INTEGER CHECK (office_size_sqft > 0),
    max_agents INTEGER CHECK (max_agents > 0),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Employee hierarchy with proper role management
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    employee_number VARCHAR(20) NOT NULL UNIQUE,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    middle_name VARCHAR(50),
    email VARCHAR(100) NOT NULL UNIQUE CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    phone VARCHAR(20) NOT NULL CHECK (phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    alternate_phone VARCHAR(20) CHECK (alternate_phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    personal_email VARCHAR(100) CHECK (personal_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    hire_date DATE NOT NULL CHECK (hire_date <= CURRENT_DATE),
    termination_date DATE CHECK (termination_date IS NULL OR termination_date >= hire_date),
    employment_type VARCHAR(20) NOT NULL CHECK (employment_type IN ('Full-time', 'Part-time', 'Contract', 'Intern')),
    employment_status VARCHAR(20) NOT NULL DEFAULT 'Active' CHECK (employment_status IN ('Active', 'Inactive', 'Terminated', 'Leave')),
    position VARCHAR(50) NOT NULL,
    department VARCHAR(50),
    office_id INTEGER NOT NULL,
    direct_manager_id INTEGER,
    hire_manager_id INTEGER,
    base_salary DECIMAL(10,2) CHECK (base_salary >= 0),
    hourly_rate DECIMAL(8,2) CHECK (hourly_rate >= 0),
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(20) CHECK (emergency_contact_phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    emergency_contact_relationship VARCHAR(50),
    date_of_birth DATE CHECK (date_of_birth < CURRENT_DATE - INTERVAL '16 years'),
    ssn_last_four VARCHAR(4) CHECK (ssn_last_four ~ '^\d{4}$'),
    is_active BOOLEAN GENERATED ALWAYS AS (employment_status = 'Active') STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (office_id) REFERENCES offices(office_id),
    FOREIGN KEY (direct_manager_id) REFERENCES employees(employee_id),
    FOREIGN KEY (hire_manager_id) REFERENCES employees(employee_id),
    CHECK ((employment_type = 'Full-time' AND base_salary IS NOT NULL) OR 
           (employment_type IN ('Part-time', 'Contract') AND hourly_rate IS NOT NULL))
);

-- Now add office manager reference (solves circular dependency)
ALTER TABLE offices ADD COLUMN office_manager_id INTEGER;
ALTER TABLE offices ADD CONSTRAINT fk_office_manager 
    FOREIGN KEY (office_manager_id) REFERENCES employees(employee_id) DEFERRABLE INITIALLY DEFERRED;

-- Enhanced agent information
CREATE TABLE agents (
    agent_id INTEGER PRIMARY KEY,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    license_state VARCHAR(2) NOT NULL CHECK (license_state IN ('NY', 'NJ', 'CT')),
    license_issue_date DATE NOT NULL,
    license_expiry_date DATE NOT NULL CHECK (license_expiry_date > license_issue_date),
    broker_license_number VARCHAR(50),
    specializations TEXT[] DEFAULT '{}',
    certifications TEXT[] DEFAULT '{}',
    languages_spoken TEXT[] DEFAULT '{"English"}',
    total_sales_count INTEGER DEFAULT 0 CHECK (total_sales_count >= 0),
    total_rental_count INTEGER DEFAULT 0 CHECK (total_rental_count >= 0),
    total_sales_volume DECIMAL(15,2) DEFAULT 0 CHECK (total_sales_volume >= 0),
    total_rental_volume DECIMAL(15,2) DEFAULT 0 CHECK (total_rental_volume >= 0),
    ytd_sales_volume DECIMAL(15,2) DEFAULT 0 CHECK (ytd_sales_volume >= 0),
    ytd_rental_volume DECIMAL(15,2) DEFAULT 0 CHECK (ytd_rental_volume >= 0),
    client_satisfaction_rating DECIMAL(3,2) CHECK (client_satisfaction_rating >= 0 AND client_satisfaction_rating <= 5),
    total_feedback_count INTEGER DEFAULT 0 CHECK (total_feedback_count >= 0),
    years_experience INTEGER DEFAULT 0 CHECK (years_experience >= 0),
    mentor_agent_id INTEGER,
    preferred_property_types TEXT[] DEFAULT '{}',
    max_concurrent_clients INTEGER DEFAULT 20 CHECK (max_concurrent_clients > 0),
    marketing_budget DECIMAL(8,2) DEFAULT 0 CHECK (marketing_budget >= 0),
    personal_website VARCHAR(200),
    linkedin_profile VARCHAR(200),
    bio TEXT,
    profile_photo_url VARCHAR(500),
    is_accepting_clients BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (agent_id) REFERENCES employees(employee_id),
    FOREIGN KEY (mentor_agent_id) REFERENCES agents(agent_id)
);

-- =============================================================================
-- ENHANCED CLIENT MANAGEMENT
-- =============================================================================

-- Comprehensive client profiles
CREATE TABLE clients (
    client_id SERIAL PRIMARY KEY,
    client_type VARCHAR(20) NOT NULL CHECK (client_type IN ('Buyer', 'Seller', 'Renter', 'Landlord', 'Investor')),
    client_status VARCHAR(20) NOT NULL DEFAULT 'Active' CHECK (client_status IN ('Active', 'Inactive', 'Prospect', 'Closed', 'Suspended')),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    middle_name VARCHAR(50),
    preferred_name VARCHAR(50),
    email VARCHAR(100) NOT NULL UNIQUE CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    phone VARCHAR(20) NOT NULL CHECK (phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    alternate_phone VARCHAR(20) CHECK (alternate_phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    work_phone VARCHAR(20) CHECK (work_phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    address_line1 VARCHAR(200),
    address_line2 VARCHAR(200),
    city VARCHAR(100),
    state VARCHAR(50),
    zip_code VARCHAR(10) CHECK (zip_code IS NULL OR zip_code ~ '^\d{5}(-\d{4})?$'),
    country VARCHAR(50) DEFAULT 'United States',
    date_of_birth DATE CHECK (date_of_birth IS NULL OR date_of_birth < CURRENT_DATE - INTERVAL '18 years'),
    occupation VARCHAR(100),
    employer VARCHAR(100),
    annual_income DECIMAL(12,2) CHECK (annual_income IS NULL OR annual_income >= 0),
    credit_score INTEGER CHECK (credit_score IS NULL OR (credit_score >= 300 AND credit_score <= 850)),
    preferred_contact_method VARCHAR(20) DEFAULT 'Email' CHECK (preferred_contact_method IN ('Email', 'Phone', 'Text', 'Mail', 'In-Person')),
    best_contact_time VARCHAR(50),
    referral_source VARCHAR(100),
    referral_agent_id INTEGER,
    primary_agent_id INTEGER,
    spouse_name VARCHAR(100),
    children_count INTEGER DEFAULT 0 CHECK (children_count >= 0),
    pet_count INTEGER DEFAULT 0 CHECK (pet_count >= 0),
    pet_types TEXT[] DEFAULT '{}',
    special_needs TEXT,
    communication_preferences JSONB DEFAULT '{}',
    marketing_opt_in BOOLEAN DEFAULT TRUE,
    data_sharing_consent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (referral_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (primary_agent_id) REFERENCES agents(agent_id)
);

-- Detailed client preferences with validation
CREATE TABLE client_preferences (
    preference_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL,
    preference_type VARCHAR(30) NOT NULL DEFAULT 'Primary' CHECK (preference_type IN ('Primary', 'Secondary', 'Investment', 'Backup')),
    property_type VARCHAR(50) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('Buy', 'Rent', 'Sell', 'Lease')),
    min_price DECIMAL(12,2) CHECK (min_price >= 0),
    max_price DECIMAL(12,2) CHECK (max_price >= 0),
    min_bedrooms INTEGER CHECK (min_bedrooms >= 0),
    max_bedrooms INTEGER CHECK (max_bedrooms >= 0),
    min_bathrooms DECIMAL(3,1) CHECK (min_bathrooms >= 0),
    max_bathrooms DECIMAL(3,1) CHECK (max_bathrooms >= 0),
    min_square_feet INTEGER CHECK (min_square_feet > 0),
    max_square_feet INTEGER CHECK (max_square_feet > 0),
    preferred_cities TEXT[] DEFAULT '{}',
    preferred_neighborhoods TEXT[] DEFAULT '{}',
    excluded_neighborhoods TEXT[] DEFAULT '{}',
    required_amenities TEXT[] DEFAULT '{}',
    preferred_amenities TEXT[] DEFAULT '{}',
    deal_breaker_features TEXT[] DEFAULT '{}',
    pet_friendly BOOLEAN,
    furnished_preference VARCHAR(20) CHECK (furnished_preference IN ('Furnished', 'Unfurnished', 'Either', 'Partial')),
    parking_required BOOLEAN DEFAULT FALSE,
    parking_type VARCHAR(30) CHECK (parking_type IN ('Garage', 'Driveway', 'Street', 'Covered', 'Any')),
    elevator_required BOOLEAN DEFAULT FALSE,
    outdoor_space_required BOOLEAN DEFAULT FALSE,
    laundry_requirement VARCHAR(20) CHECK (laundry_requirement IN ('In-Unit', 'In-Building', 'Nearby', 'None')),
    move_in_date DATE,
    move_out_date DATE,
    lease_duration_months INTEGER CHECK (lease_duration_months IS NULL OR lease_duration_months > 0),
    commute_locations TEXT[] DEFAULT '{}',
    max_commute_time INTEGER CHECK (max_commute_time IS NULL OR max_commute_time > 0),
    school_district_preference TEXT[] DEFAULT '{}',
    lifestyle_preferences JSONB DEFAULT '{}',
    additional_notes TEXT,
    priority_score INTEGER DEFAULT 5 CHECK (priority_score >= 1 AND priority_score <= 10),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
    CHECK (min_price IS NULL OR max_price IS NULL OR min_price <= max_price),
    CHECK (min_bedrooms IS NULL OR max_bedrooms IS NULL OR min_bedrooms <= max_bedrooms),
    CHECK (min_bathrooms IS NULL OR max_bathrooms IS NULL OR min_bathrooms <= max_bathrooms),
    CHECK (min_square_feet IS NULL OR max_square_feet IS NULL OR min_square_feet <= max_square_feet),
    CHECK (move_in_date IS NULL OR move_out_date IS NULL OR move_in_date < move_out_date)
);

-- =============================================================================
-- ENHANCED LOCATION AND MARKET DATA
-- =============================================================================

-- Comprehensive neighborhood analytics
CREATE TABLE neighborhoods (
    neighborhood_id SERIAL PRIMARY KEY,
    neighborhood_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL CHECK (state IN ('NY', 'NJ', 'CT')),
    county VARCHAR(50),
    zip_codes TEXT[] DEFAULT '{}',
    boundary_coordinates POLYGON,
    center_latitude DECIMAL(10,7),
    center_longitude DECIMAL(10,7),
    safety_rating DECIMAL(3,2) CHECK (safety_rating IS NULL OR (safety_rating >= 0 AND safety_rating <= 5)),
    walkability_score INTEGER CHECK (walkability_score IS NULL OR (walkability_score >= 0 AND walkability_score <= 100)),
    transit_score INTEGER CHECK (transit_score IS NULL OR (transit_score >= 0 AND transit_score <= 100)),
    bike_score INTEGER CHECK (bike_score IS NULL OR (bike_score >= 0 AND bike_score <= 100)),
    public_transportation_lines TEXT[] DEFAULT '{}',
    nearby_airports TEXT[] DEFAULT '{}',
    major_highways TEXT[] DEFAULT '{}',
    nearby_parks TEXT[] DEFAULT '{}',
    shopping_centers TEXT[] DEFAULT '{}',
    restaurants_dining TEXT[] DEFAULT '{}',
    entertainment_venues TEXT[] DEFAULT '{}',
    healthcare_facilities TEXT[] DEFAULT '{}',
    grocery_stores TEXT[] DEFAULT '{}',
    average_home_price DECIMAL(12,2) CHECK (average_home_price IS NULL OR average_home_price >= 0),
    average_rental_price DECIMAL(8,2) CHECK (average_rental_price IS NULL OR average_rental_price >= 0),
    price_per_sqft DECIMAL(8,2) CHECK (price_per_sqft IS NULL OR price_per_sqft >= 0),
    rental_price_per_sqft DECIMAL(6,2) CHECK (rental_price_per_sqft IS NULL OR rental_price_per_sqft >= 0),
    population_density INTEGER CHECK (population_density IS NULL OR population_density >= 0),
    median_age DECIMAL(4,1) CHECK (median_age IS NULL OR median_age >= 0),
    median_household_income DECIMAL(10,2) CHECK (median_household_income IS NULL OR median_household_income >= 0),
    unemployment_rate DECIMAL(5,2) CHECK (unemployment_rate IS NULL OR (unemployment_rate >= 0 AND unemployment_rate <= 100)),
    crime_rate DECIMAL(8,2) CHECK (crime_rate IS NULL OR crime_rate >= 0),
    property_tax_rate DECIMAL(5,4) CHECK (property_tax_rate IS NULL OR property_tax_rate >= 0),
    school_rating DECIMAL(3,2) CHECK (school_rating IS NULL OR (school_rating >= 0 AND school_rating <= 5)),
    noise_level VARCHAR(20) CHECK (noise_level IN ('Quiet', 'Moderate', 'Busy', 'Very Busy', 'Unknown')),
    air_quality_index INTEGER CHECK (air_quality_index IS NULL OR (air_quality_index >= 0 AND air_quality_index <= 500)),
    demographics JSONB DEFAULT '{}',
    market_trends JSONB DEFAULT '{}',
    description TEXT,
    data_last_updated DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Enhanced school information
CREATE TABLE schools (
    school_id SERIAL PRIMARY KEY,
    school_name VARCHAR(150) NOT NULL,
    school_type VARCHAR(30) NOT NULL CHECK (school_type IN ('Elementary', 'Middle', 'High', 'K-12', 'Private', 'Charter', 'Magnet', 'Specialized')),
    school_level VARCHAR(20) CHECK (school_level IN ('Elementary', 'Secondary', 'Both')),
    address_line1 VARCHAR(200) NOT NULL,
    address_line2 VARCHAR(200),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL CHECK (state IN ('NY', 'NJ', 'CT')),
    zip_code VARCHAR(10) NOT NULL CHECK (zip_code ~ '^\d{5}(-\d{4})?$'),
    phone VARCHAR(20) CHECK (phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    website VARCHAR(200),
    email VARCHAR(100) CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    principal_name VARCHAR(100),
    district_name VARCHAR(100),
    district_code VARCHAR(20),
    enrollment INTEGER CHECK (enrollment IS NULL OR enrollment >= 0),
    student_teacher_ratio DECIMAL(4,1) CHECK (student_teacher_ratio IS NULL OR student_teacher_ratio > 0),
    graduation_rate DECIMAL(5,2) CHECK (graduation_rate IS NULL OR (graduation_rate >= 0 AND graduation_rate <= 100)),
    college_readiness_rate DECIMAL(5,2) CHECK (college_readiness_rate IS NULL OR (college_readiness_rate >= 0 AND college_readiness_rate <= 100)),
    state_rating VARCHAR(10),
    federal_rating VARCHAR(10),
    test_scores JSONB DEFAULT '{}',
    grade_levels VARCHAR(50),
    special_programs TEXT[] DEFAULT '{}',
    extracurricular_activities TEXT[] DEFAULT '{}',
    language_programs TEXT[] DEFAULT '{}',
    tuition_annual DECIMAL(8,2) CHECK (tuition_annual IS NULL OR tuition_annual >= 0),
    acceptance_rate DECIMAL(5,2) CHECK (acceptance_rate IS NULL OR (acceptance_rate >= 0 AND acceptance_rate <= 100)),
    neighborhood_id INTEGER,
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    boundary_zone POLYGON,
    transportation_provided BOOLEAN DEFAULT FALSE,
    uniform_required BOOLEAN DEFAULT FALSE,
    calendar_type VARCHAR(20) CHECK (calendar_type IN ('Traditional', 'Year-Round', 'Modified', 'Other')),
    start_time TIME,
    end_time TIME,
    data_last_updated DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (neighborhood_id) REFERENCES neighborhoods(neighborhood_id)
);

-- =============================================================================
-- ENHANCED PROPERTY MANAGEMENT
-- =============================================================================

-- Comprehensive property inventory
CREATE TABLE properties (
    property_id SERIAL PRIMARY KEY,
    mls_number VARCHAR(50) UNIQUE,
    property_type VARCHAR(50) NOT NULL CHECK (property_type IN ('Apartment', 'House', 'Condo', 'Townhouse', 'Loft', 'Studio', 'Duplex', 'Penthouse', 'Commercial', 'Land', 'Multi-Family')),
    property_subtype VARCHAR(50),
    address_line1 VARCHAR(200) NOT NULL,
    address_line2 VARCHAR(200),
    unit_number VARCHAR(20),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL CHECK (state IN ('NY', 'NJ', 'CT')),
    zip_code VARCHAR(10) NOT NULL CHECK (zip_code ~ '^\d{5}(-\d{4})?$'),
    neighborhood_id INTEGER,
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    parcel_id VARCHAR(50),
    tax_id VARCHAR(50),
    listing_price DECIMAL(12,2) NOT NULL CHECK (listing_price > 0),
    original_listing_price DECIMAL(12,2) CHECK (original_listing_price IS NULL OR original_listing_price > 0),
    price_per_sqft DECIMAL(8,2) CHECK (price_per_sqft IS NULL OR price_per_sqft > 0),
    square_feet INTEGER CHECK (square_feet IS NULL OR square_feet > 0),
    interior_sqft INTEGER CHECK (interior_sqft IS NULL OR interior_sqft > 0),
    exterior_sqft INTEGER CHECK (exterior_sqft IS NULL OR exterior_sqft >= 0),
    bedrooms INTEGER NOT NULL CHECK (bedrooms >= 0),
    bathrooms DECIMAL(3,1) NOT NULL CHECK (bathrooms >= 0),
    half_bathrooms INTEGER DEFAULT 0 CHECK (half_bathrooms >= 0),
    floors_in_unit INTEGER CHECK (floors_in_unit IS NULL OR floors_in_unit >= 1),
    building_floors INTEGER CHECK (building_floors IS NULL OR building_floors >= 1),
    unit_floor INTEGER CHECK (unit_floor IS NULL OR unit_floor >= 0),
    year_built INTEGER CHECK (year_built IS NULL OR (year_built >= 1800 AND year_built <= EXTRACT(YEAR FROM CURRENT_DATE))),
    year_renovated INTEGER CHECK (year_renovated IS NULL OR (year_renovated >= year_built AND year_renovated <= EXTRACT(YEAR FROM CURRENT_DATE))),
    lot_size DECIMAL(10,2) CHECK (lot_size IS NULL OR lot_size > 0),
    lot_dimensions VARCHAR(50),
    parking_spaces INTEGER DEFAULT 0 CHECK (parking_spaces >= 0),
    parking_type VARCHAR(50),
    garage_spaces INTEGER DEFAULT 0 CHECK (garage_spaces >= 0),
    
    -- Amenities and Features
    amenities TEXT[] DEFAULT '{}',
    appliances_included TEXT[] DEFAULT '{}',
    heating_type VARCHAR(50),
    cooling_type VARCHAR(50),
    flooring_types TEXT[] DEFAULT '{}',
    window_types TEXT[] DEFAULT '{}',
    kitchen_features TEXT[] DEFAULT '{}',
    bathroom_features TEXT[] DEFAULT '{}',
    storage_features TEXT[] DEFAULT '{}',
    outdoor_features TEXT[] DEFAULT '{}',
    building_amenities TEXT[] DEFAULT '{}',
    utilities_included TEXT[] DEFAULT '{}',
    
    -- Policies and Restrictions
    pet_policy VARCHAR(100),
    pet_deposit DECIMAL(8,2) DEFAULT 0 CHECK (pet_deposit >= 0),
    smoking_policy VARCHAR(50),
    furnished_status VARCHAR(20) CHECK (furnished_status IN ('Furnished', 'Unfurnished', 'Partially Furnished', 'Negotiable')),
    lease_terms TEXT[] DEFAULT '{}',
    rental_restrictions TEXT,
    
    -- Listing Information
    listing_status VARCHAR(20) NOT NULL DEFAULT 'Available' 
        CHECK (listing_status IN ('Available', 'Under Contract', 'Sold', 'Rented', 'Off Market', 'Pending', 'Withdrawn', 'Expired', 'Coming Soon')),
    previous_status VARCHAR(20),
    listing_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status_change_date DATE DEFAULT CURRENT_DATE,
    expiration_date DATE,
    listing_agent_id INTEGER NOT NULL,
    co_listing_agent_id INTEGER,
    listing_office_id INTEGER NOT NULL,
    seller_disclosure_available BOOLEAN DEFAULT FALSE,
    virtual_tour_url VARCHAR(300),
    video_tour_url VARCHAR(300),
    property_website VARCHAR(300),
    
    -- Marketing and Display
    property_description TEXT,
    private_agent_notes TEXT,
    showing_instructions TEXT,
    lockbox_code VARCHAR(20),
    security_system VARCHAR(100),
    is_featured BOOLEAN DEFAULT FALSE,
    featured_until DATE,
    marketing_package VARCHAR(50),
    photos_count INTEGER DEFAULT 0 CHECK (photos_count >= 0),
    virtual_staging BOOLEAN DEFAULT FALSE,
    
    -- Financial Information
    monthly_hoa_fee DECIMAL(8,2) DEFAULT 0 CHECK (monthly_hoa_fee >= 0),
    annual_property_tax DECIMAL(10,2) CHECK (annual_property_tax IS NULL OR annual_property_tax >= 0),
    monthly_maintenance_fee DECIMAL(8,2) DEFAULT 0 CHECK (monthly_maintenance_fee >= 0),
    utility_costs JSONB DEFAULT '{}',
    
    -- Analytics
    days_on_market INTEGER GENERATED ALWAYS AS (CURRENT_DATE - listing_date) STORED,
    price_changes_count INTEGER DEFAULT 0 CHECK (price_changes_count >= 0),
    view_count INTEGER DEFAULT 0 CHECK (view_count >= 0),
    inquiry_count INTEGER DEFAULT 0 CHECK (inquiry_count >= 0),
    showing_count INTEGER DEFAULT 0 CHECK (showing_count >= 0),
    
    -- System Fields
    data_source VARCHAR(50) DEFAULT 'Internal',
    external_id VARCHAR(100),
    sync_status VARCHAR(20) DEFAULT 'Current' CHECK (sync_status IN ('Current', 'Pending', 'Error', 'Disabled')),
    last_sync_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (neighborhood_id) REFERENCES neighborhoods(neighborhood_id),
    FOREIGN KEY (listing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (co_listing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (listing_office_id) REFERENCES offices(office_id),
    
    CHECK (unit_floor IS NULL OR building_floors IS NULL OR unit_floor <= building_floors),
    CHECK (garage_spaces <= parking_spaces)
);

-- Property price history tracking
CREATE TABLE property_price_history (
    price_history_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    old_price DECIMAL(12,2) NOT NULL CHECK (old_price > 0),
    new_price DECIMAL(12,2) NOT NULL CHECK (new_price > 0),
    price_change_amount DECIMAL(12,2) GENERATED ALWAYS AS (new_price - old_price) STORED,
    price_change_percentage DECIMAL(5,2) GENERATED ALWAYS AS (((new_price - old_price) / old_price) * 100) STORED,
    change_reason VARCHAR(100),
    changed_by INTEGER NOT NULL,
    change_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (changed_by) REFERENCES employees(employee_id)
);

-- Enhanced property photos with metadata
CREATE TABLE property_photos (
    photo_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    photo_url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    photo_title VARCHAR(200),
    photo_description VARCHAR(500),
    photo_type VARCHAR(50) NOT NULL CHECK (photo_type IN ('Exterior', 'Interior', 'Kitchen', 'Bathroom', 'Bedroom', 'Living Room', 'Dining Room', 'Office', 'Basement', 'Attic', 'Garage', 'Balcony', 'Patio', 'Garden', 'Pool', 'Amenity', 'Floor Plan', 'Virtual Tour', 'Drone', 'Street View')),
    room_name VARCHAR(100),
    display_order INTEGER DEFAULT 1 CHECK (display_order > 0),
    is_primary BOOLEAN DEFAULT FALSE,
    is_featured BOOLEAN DEFAULT FALSE,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uploaded_by INTEGER NOT NULL,
    file_name VARCHAR(255),
    file_size_kb INTEGER CHECK (file_size_kb IS NULL OR file_size_kb > 0),
    image_width INTEGER CHECK (image_width IS NULL OR image_width > 0),
    image_height INTEGER CHECK (image_height IS NULL OR image_height > 0),
    camera_make VARCHAR(100),
    camera_model VARCHAR(100),
    photo_taken_date TIMESTAMP,
    gps_latitude DECIMAL(10,7),
    gps_longitude DECIMAL(10,7),
    is_active BOOLEAN DEFAULT TRUE,
    moderation_status VARCHAR(20) DEFAULT 'Approved' CHECK (moderation_status IN ('Pending', 'Approved', 'Rejected', 'Flagged')),
    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (uploaded_by) REFERENCES employees(employee_id)
);

-- Comprehensive property documents management
CREATE TABLE property_documents (
    document_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    document_name VARCHAR(200) NOT NULL,
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN ('Floor Plan', 'Property Disclosure', 'HOA Documents', 'Condo Bylaws', 'Title Report', 'Deed', 'Survey', 'Inspection Report', 'Appraisal', 'Environmental Report', 'Zoning Certificate', 'Certificate of Occupancy', 'Utility Bills', 'Tax Records', 'Insurance Documents', 'Lease Agreement', 'Marketing Flyer', 'Brochure', 'Legal Documents', 'Other')),
    document_category VARCHAR(50) CHECK (document_category IN ('Legal', 'Financial', 'Technical', 'Marketing', 'Administrative', 'Regulatory')),
    document_url VARCHAR(500) NOT NULL,
    file_name VARCHAR(255),
    file_size_kb INTEGER CHECK (file_size_kb IS NULL OR file_size_kb > 0),
    mime_type VARCHAR(100),
    document_date DATE,
    expiration_date DATE,
    version_number VARCHAR(20) DEFAULT '1.0',
    uploaded_by INTEGER NOT NULL,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed_at TIMESTAMP,
    access_count INTEGER DEFAULT 0 CHECK (access_count >= 0),
    is_public BOOLEAN DEFAULT FALSE,
    requires_approval BOOLEAN DEFAULT FALSE,
    approval_status VARCHAR(20) DEFAULT 'Approved' CHECK (approval_status IN ('Pending', 'Approved', 'Rejected')),
    approved_by INTEGER,
    approved_at TIMESTAMP,
    tags TEXT[] DEFAULT '{}',
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (uploaded_by) REFERENCES employees(employee_id),
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id),
    CHECK (expiration_date IS NULL OR expiration_date > document_date)
);

-- Property viewing and showing tracking
CREATE TABLE property_showings (
    showing_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    showing_type VARCHAR(30) NOT NULL CHECK (showing_type IN ('Private Showing', 'Open House', 'Broker Preview', 'Virtual Tour', 'Self-Guided', 'Video Call')),
    scheduled_date DATE NOT NULL,
    scheduled_start_time TIME NOT NULL,
    scheduled_end_time TIME NOT NULL,
    actual_start_time TIME,
    actual_end_time TIME,
    showing_agent_id INTEGER NOT NULL,
    client_id INTEGER,
    attendee_count INTEGER DEFAULT 1 CHECK (attendee_count >= 0),
    attendee_names TEXT[] DEFAULT '{}',
    contact_info JSONB DEFAULT '{}',
    showing_status VARCHAR(20) NOT NULL DEFAULT 'Scheduled' 
        CHECK (showing_status IN ('Scheduled', 'Confirmed', 'In Progress', 'Completed', 'Cancelled', 'No Show', 'Rescheduled')),
    cancellation_reason VARCHAR(200),
    feedback_received BOOLEAN DEFAULT FALSE,
    interest_level VARCHAR(20) CHECK (interest_level IN ('Very High', 'High', 'Medium', 'Low', 'None')),
    showing_notes TEXT,
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_date DATE,
    follow_up_completed BOOLEAN DEFAULT FALSE,
    lockbox_used BOOLEAN DEFAULT FALSE,
    security_deposit_required DECIMAL(8,2) DEFAULT 0 CHECK (security_deposit_required >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (showing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (client_id) REFERENCES clients(client_id),
    CHECK (scheduled_end_time > scheduled_start_time),
    CHECK (actual_end_time IS NULL OR actual_start_time IS NULL OR actual_end_time >= actual_start_time)
);

-- =============================================================================
-- ADVANCED APPOINTMENT AND EVENT MANAGEMENT
-- =============================================================================

-- Enhanced appointment system
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    appointment_type VARCHAR(50) NOT NULL CHECK (appointment_type IN ('Property Showing', 'Initial Consultation', 'Buyer Consultation', 'Seller Consultation', 'Market Analysis', 'Contract Review', 'Inspection', 'Appraisal', 'Closing Preparation', 'Closing', 'Follow-up', 'Listing Presentation', 'Price Adjustment Meeting', 'Document Signing', 'Virtual Meeting', 'Phone Consultation', 'Other')),
    appointment_category VARCHAR(30) CHECK (appointment_category IN ('Sales', 'Rental', 'Consultation', 'Administrative', 'Legal', 'Marketing')),
    primary_agent_id INTEGER NOT NULL,
    secondary_agent_id INTEGER,
    client_id INTEGER NOT NULL,
    property_id INTEGER,
    related_transaction_id INTEGER,
    
    -- Scheduling Details
    appointment_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    estimated_duration INTEGER GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (end_time - start_time))/60) STORED,
    timezone VARCHAR(50) DEFAULT 'America/New_York',
    
    -- Location Information
    location_type VARCHAR(30) NOT NULL CHECK (location_type IN ('Property', 'Office', 'Client Home', 'Coffee Shop', 'Restaurant', 'Virtual', 'Phone', 'Other')),
    meeting_address VARCHAR(300),
    meeting_room VARCHAR(50),
    virtual_meeting_link VARCHAR(300),
    virtual_meeting_id VARCHAR(100),
    virtual_meeting_password VARCHAR(50),
    
    -- Status and Management
    appointment_status VARCHAR(20) NOT NULL DEFAULT 'Scheduled' 
        CHECK (appointment_status IN ('Scheduled', 'Confirmed', 'Reminded', 'In Progress', 'Completed', 'Cancelled', 'No Show', 'Rescheduled', 'Postponed')),
    confirmation_status VARCHAR(20) DEFAULT 'Pending' CHECK (confirmation_status IN ('Pending', 'Confirmed', 'Declined', 'Tentative')),
    reminder_sent BOOLEAN DEFAULT FALSE,
    reminder_sent_at TIMESTAMP,
    
    -- Agenda and Preparation
    meeting_agenda TEXT,
    preparation_notes TEXT,
    documents_needed TEXT[] DEFAULT '{}',
    materials_to_bring TEXT[] DEFAULT '{}',
    
    -- Outcome and Follow-up
    meeting_notes TEXT,
    outcome VARCHAR(50) CHECK (outcome IN ('Very Positive', 'Positive', 'Neutral', 'Negative', 'No Outcome', 'Interested', 'Not Interested', 'Needs More Info', 'Ready to Proceed', 'Contract Signed', 'Listing Signed', 'Referral Given', 'Other')),
    action_items TEXT[] DEFAULT '{}',
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_date DATE,
    follow_up_type VARCHAR(30),
    follow_up_completed BOOLEAN DEFAULT FALSE,
    
    -- Additional Information
    attendee_count INTEGER DEFAULT 2 CHECK (attendee_count >= 1),
    other_attendees TEXT[] DEFAULT '{}',
    cancellation_reason VARCHAR(200),
    rescheduled_from INTEGER,
    rescheduled_to INTEGER,
    recurring_pattern VARCHAR(50),
    parent_appointment_id INTEGER,
    
    -- System Fields
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (primary_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (secondary_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (client_id) REFERENCES clients(client_id),
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (rescheduled_from) REFERENCES appointments(appointment_id),
    FOREIGN KEY (rescheduled_to) REFERENCES appointments(appointment_id),
    FOREIGN KEY (parent_appointment_id) REFERENCES appointments(appointment_id),
    FOREIGN KEY (created_by) REFERENCES employees(employee_id),
    
    CHECK (end_time > start_time),
    CHECK (appointment_date >= CURRENT_DATE - INTERVAL '1 year'),
    CHECK (follow_up_date IS NULL OR follow_up_date > appointment_date)
);

-- Enhanced open house management
CREATE TABLE open_houses (
    open_house_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    hosting_agent_id INTEGER NOT NULL,
    co_hosting_agent_id INTEGER,
    
    -- Event Details
    event_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    setup_time TIME,
    cleanup_time TIME,
    
    -- Status and Management
    event_status VARCHAR(20) NOT NULL DEFAULT 'Scheduled' 
        CHECK (event_status IN ('Scheduled', 'Confirmed', 'Preparation', 'Active', 'Completed', 'Cancelled', 'Postponed')),
    cancellation_reason VARCHAR(200),
    weather_backup_plan TEXT,
    
    -- Registration and Attendance
    registration_required BOOLEAN DEFAULT FALSE,
    max_attendees INTEGER CHECK (max_attendees IS NULL OR max_attendees > 0),
    actual_attendee_count INTEGER DEFAULT 0 CHECK (actual_attendee_count >= 0),
    registered_attendee_count INTEGER DEFAULT 0 CHECK (registered_attendee_count >= 0),
    walk_in_count INTEGER DEFAULT 0 CHECK (walk_in_count >= 0),
    agent_attendee_count INTEGER DEFAULT 0 CHECK (agent_attendee_count >= 0),
    
    -- Lead Generation
    leads_generated INTEGER DEFAULT 0 CHECK (leads_generated >= 0),
    qualified_leads INTEGER DEFAULT 0 CHECK (qualified_leads >= 0),
    offers_received INTEGER DEFAULT 0 CHECK (offers_received >= 0),
    follow_up_appointments INTEGER DEFAULT 0 CHECK (follow_up_appointments >= 0),
    
    -- Marketing and Promotion
    marketing_channels TEXT[] DEFAULT '{}',
    advertising_budget DECIMAL(8,2) DEFAULT 0 CHECK (advertising_budget >= 0),
    promotional_materials TEXT[] DEFAULT '{}',
    special_features TEXT[] DEFAULT '{}',
    
    -- Event Setup
    refreshments_provided BOOLEAN DEFAULT FALSE,
    refreshment_budget DECIMAL(6,2) DEFAULT 0 CHECK (refreshment_budget >= 0),
    signage_installed BOOLEAN DEFAULT FALSE,
    security_present BOOLEAN DEFAULT FALSE,
    parking_arrangements TEXT,
    guest_parking_available BOOLEAN DEFAULT TRUE,
    
    -- Feedback and Results
    visitor_feedback_summary TEXT,
    agent_feedback TEXT,
    event_success_rating INTEGER CHECK (event_success_rating IS NULL OR (event_success_rating >= 1 AND event_success_rating <= 5)),
    lessons_learned TEXT,
    recommendations TEXT,
    
    -- Financial
    total_cost DECIMAL(8,2) DEFAULT 0 CHECK (total_cost >= 0),
    cost_breakdown JSONB DEFAULT '{}',
    
    -- System Fields
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (hosting_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (co_hosting_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (created_by) REFERENCES employees(employee_id),
    
    CHECK (end_time > start_time),
    CHECK (setup_time IS NULL OR setup_time <= start_time),
    CHECK (cleanup_time IS NULL OR cleanup_time >= end_time),
    CHECK (qualified_leads <= leads_generated)
);

-- Open house visitor registration and tracking
CREATE TABLE open_house_visitors (
    visitor_id SERIAL PRIMARY KEY,
    open_house_id INTEGER NOT NULL,
    client_id INTEGER,
    
    -- Visitor Information
    visitor_type VARCHAR(20) NOT NULL CHECK (visitor_type IN ('Registered Client', 'Walk-in', 'Agent', 'Neighbor', 'Investor', 'Other')),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100) CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    phone VARCHAR(20) CHECK (phone IS NULL OR phone ~ '^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'),
    company VARCHAR(100),
    
    -- Visit Details
    check_in_time TIME,
    check_out_time TIME,
    visit_duration INTEGER GENERATED ALWAYS AS (
        CASE 
            WHEN check_in_time IS NOT NULL AND check_out_time IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (check_out_time - check_in_time))/60 
            ELSE NULL 
        END
    ) STORED,
    
    -- Engagement and Interest
    interest_level VARCHAR(20) CHECK (interest_level IN ('Very High', 'High', 'Medium', 'Low', 'Just Looking', 'No Interest')),
    areas_of_interest TEXT[] DEFAULT '{}',
    questions_asked TEXT[] DEFAULT '{}',
    concerns_raised TEXT[] DEFAULT '{}',
    
    -- Qualification
    pre_qualified BOOLEAN,
    budget_range VARCHAR(50),
    timeline VARCHAR(50),
    current_living_situation VARCHAR(100),
    
    -- Feedback and Follow-up
    visitor_feedback TEXT,
    agent_notes TEXT,
    follow_up_requested BOOLEAN DEFAULT FALSE,
    follow_up_method VARCHAR(30) CHECK (follow_up_method IN ('Email', 'Phone', 'Text', 'Mail', 'In-Person', 'No Follow-up')),
    follow_up_completed BOOLEAN DEFAULT FALSE,
    follow_up_date DATE,
    
    -- Lead Classification
    lead_quality VARCHAR(20) CHECK (lead_quality IN ('Hot', 'Warm', 'Cold', 'Not Qualified', 'Referral Source')),
    lead_source VARCHAR(50),
    assigned_agent_id INTEGER,
    
    -- Privacy and Compliance
    marketing_opt_in BOOLEAN DEFAULT FALSE,
    data_sharing_consent BOOLEAN DEFAULT FALSE,
    contact_preference VARCHAR(30),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (open_house_id) REFERENCES open_houses(open_house_id) ON DELETE CASCADE,
    FOREIGN KEY (client_id) REFERENCES clients(client_id),
    FOREIGN KEY (assigned_agent_id) REFERENCES agents(agent_id),
    
    CHECK ((client_id IS NOT NULL) OR (first_name IS NOT NULL AND last_name IS NOT NULL)),
    CHECK (check_out_time IS NULL OR check_in_time IS NULL OR check_out_time >= check_in_time)
);

-- Continue with remaining tables in next response due to length limits... 

-- =============================================================================
-- ENHANCED TRANSACTION MANAGEMENT
-- =============================================================================

-- Comprehensive sales transactions
CREATE TABLE sales_transactions (
    transaction_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    buyer_client_id INTEGER NOT NULL,
    seller_client_id INTEGER,
    listing_agent_id INTEGER NOT NULL,
    buyer_agent_id INTEGER,
    transaction_coordinator_id INTEGER,
    
    -- Transaction Details
    transaction_type VARCHAR(20) NOT NULL DEFAULT 'Sale' CHECK (transaction_type IN ('Sale', 'Purchase', 'New Construction')),
    sale_price DECIMAL(12,2) NOT NULL CHECK (sale_price > 0),
    original_asking_price DECIMAL(12,2) CHECK (original_asking_price IS NULL OR original_asking_price > 0),
    price_negotiation_count INTEGER DEFAULT 0 CHECK (price_negotiation_count >= 0),
    
    -- Important Dates
    contract_date DATE NOT NULL,
    expected_closing_date DATE,
    actual_closing_date DATE,
    listing_date DATE,
    first_showing_date DATE,
    
    -- Financing Information
    financing_type VARCHAR(50) CHECK (financing_type IN ('Cash', 'Conventional', 'FHA', 'VA', 'USDA', 'Jumbo', 'Hard Money', 'Other')),
    down_payment_amount DECIMAL(12,2) CHECK (down_payment_amount IS NULL OR down_payment_amount >= 0),
    down_payment_percentage DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN sale_price > 0 AND down_payment_amount IS NOT NULL 
        THEN (down_payment_amount / sale_price) * 100 
        ELSE NULL END
    ) STORED,
    loan_amount DECIMAL(12,2) CHECK (loan_amount IS NULL OR loan_amount >= 0),
    interest_rate DECIMAL(5,4) CHECK (interest_rate IS NULL OR interest_rate >= 0),
    loan_term_years INTEGER CHECK (loan_term_years IS NULL OR loan_term_years > 0),
    
    -- Transaction Status and Contingencies
    transaction_status VARCHAR(30) NOT NULL DEFAULT 'Under Contract' 
        CHECK (transaction_status IN ('Under Contract', 'Pending Inspection', 'Pending Appraisal', 'Pending Financing', 'Clear to Close', 'Closed', 'Cancelled', 'Failed')),
    cancellation_reason VARCHAR(200),
    inspection_contingency BOOLEAN DEFAULT TRUE,
    inspection_contingency_date DATE,
    inspection_waived BOOLEAN DEFAULT FALSE,
    financing_contingency BOOLEAN DEFAULT TRUE,
    financing_contingency_date DATE,
    appraisal_contingency BOOLEAN DEFAULT TRUE,
    appraisal_contingency_date DATE,
    appraisal_amount DECIMAL(12,2) CHECK (appraisal_amount IS NULL OR appraisal_amount > 0),
    
    -- Closing Information
    closing_attorney VARCHAR(100),
    title_company VARCHAR(100),
    escrow_agent VARCHAR(100),
    closing_costs_buyer DECIMAL(10,2) CHECK (closing_costs_buyer IS NULL OR closing_costs_buyer >= 0),
    closing_costs_seller DECIMAL(10,2) CHECK (closing_costs_seller IS NULL OR closing_costs_seller >= 0),
    prorations DECIMAL(8,2) DEFAULT 0,
    credits_to_buyer DECIMAL(8,2) DEFAULT 0 CHECK (credits_to_buyer >= 0),
    
    -- Performance Metrics
    days_to_contract INTEGER GENERATED ALWAYS AS (
        CASE WHEN listing_date IS NOT NULL 
        THEN contract_date - listing_date 
        ELSE NULL END
    ) STORED,
    days_to_close INTEGER GENERATED ALWAYS AS (
        CASE WHEN actual_closing_date IS NOT NULL 
        THEN actual_closing_date - contract_date 
        ELSE NULL END
    ) STORED,
    
    -- Additional Information
    multiple_offers BOOLEAN DEFAULT FALSE,
    offer_count INTEGER DEFAULT 1 CHECK (offer_count >= 0),
    highest_offer_amount DECIMAL(12,2) CHECK (highest_offer_amount IS NULL OR highest_offer_amount >= 0),
    transaction_notes TEXT,
    private_notes TEXT,
    
    -- System Fields
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (buyer_client_id) REFERENCES clients(client_id),
    FOREIGN KEY (seller_client_id) REFERENCES clients(client_id),
    FOREIGN KEY (listing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (buyer_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (transaction_coordinator_id) REFERENCES employees(employee_id),
    FOREIGN KEY (created_by) REFERENCES employees(employee_id),
    
    CHECK (actual_closing_date IS NULL OR actual_closing_date >= contract_date),
    CHECK (sale_price >= COALESCE(down_payment_amount, 0)),
    CHECK (expected_closing_date IS NULL OR expected_closing_date >= contract_date)
);

-- Enhanced rental transactions
CREATE TABLE rental_transactions (
    rental_transaction_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    tenant_client_id INTEGER NOT NULL,
    landlord_client_id INTEGER,
    listing_agent_id INTEGER NOT NULL,
    tenant_agent_id INTEGER,
    
    -- Rental Terms
    monthly_rent DECIMAL(8,2) NOT NULL CHECK (monthly_rent > 0),
    security_deposit DECIMAL(8,2) NOT NULL CHECK (security_deposit >= 0),
    last_month_rent DECIMAL(8,2) DEFAULT 0 CHECK (last_month_rent >= 0),
    broker_fee DECIMAL(8,2) DEFAULT 0 CHECK (broker_fee >= 0),
    broker_fee_percentage DECIMAL(5,2) GENERATED ALWAYS AS (
        CASE WHEN monthly_rent > 0 AND broker_fee > 0 
        THEN (broker_fee / monthly_rent) * 100 
        ELSE NULL END
    ) STORED,
    pet_deposit DECIMAL(8,2) DEFAULT 0 CHECK (pet_deposit >= 0),
    other_deposits DECIMAL(8,2) DEFAULT 0 CHECK (other_deposits >= 0),
    
    -- Lease Dates and Duration
    lease_start_date DATE NOT NULL,
    lease_end_date DATE NOT NULL,
    lease_duration_months INTEGER GENERATED ALWAYS AS (
        EXTRACT(MONTH FROM AGE(lease_end_date, lease_start_date)) + 
        EXTRACT(YEAR FROM AGE(lease_end_date, lease_start_date)) * 12
    ) STORED,
    lease_type VARCHAR(30) CHECK (lease_type IN ('Fixed Term', 'Month-to-Month', 'Renewal', 'Extension')),
    renewal_option BOOLEAN DEFAULT FALSE,
    automatic_renewal BOOLEAN DEFAULT FALSE,
    
    -- Application and Approval Process
    application_date DATE NOT NULL,
    application_fee DECIMAL(6,2) DEFAULT 0 CHECK (application_fee >= 0),
    credit_check_date DATE,
    credit_score INTEGER CHECK (credit_score IS NULL OR (credit_score >= 300 AND credit_score <= 850)),
    background_check_date DATE,
    employment_verification_date DATE,
    reference_check_date DATE,
    approval_date DATE,
    lease_signing_date DATE,
    move_in_date DATE,
    
    -- Rental Status
    rental_status VARCHAR(20) NOT NULL DEFAULT 'Applied' 
        CHECK (rental_status IN ('Applied', 'Under Review', 'Approved', 'Lease Signed', 'Active', 'Completed', 'Terminated', 'Cancelled', 'Evicted')),
    move_in_completed BOOLEAN DEFAULT FALSE,
    move_out_date DATE,
    early_termination BOOLEAN DEFAULT FALSE,
    early_termination_fee DECIMAL(8,2) CHECK (early_termination_fee IS NULL OR early_termination_fee >= 0),
    
    -- Additional Terms
    utilities_included TEXT[] DEFAULT '{}',
    parking_included BOOLEAN DEFAULT FALSE,
    parking_spaces INTEGER DEFAULT 0 CHECK (parking_spaces >= 0),
    storage_included BOOLEAN DEFAULT FALSE,
    furnished BOOLEAN DEFAULT FALSE,
    pets_allowed BOOLEAN DEFAULT FALSE,
    smoking_allowed BOOLEAN DEFAULT FALSE,
    subletting_allowed BOOLEAN DEFAULT FALSE,
    
    -- Financial Information
    annual_rent_amount DECIMAL(10,2) GENERATED ALWAYS AS (monthly_rent * 12) STORED,
    total_upfront_costs DECIMAL(10,2) GENERATED ALWAYS AS (
        monthly_rent + security_deposit + last_month_rent + broker_fee + pet_deposit + other_deposits
    ) STORED,
    
    -- Documentation
    lease_document_url VARCHAR(500),
    application_document_url VARCHAR(500),
    
    -- Performance Metrics
    days_to_approval INTEGER GENERATED ALWAYS AS (
        CASE WHEN approval_date IS NOT NULL 
        THEN approval_date - application_date 
        ELSE NULL END
    ) STORED,
    
    -- Notes
    rental_notes TEXT,
    private_notes TEXT,
    special_conditions TEXT,
    
    -- System Fields
    created_by INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (tenant_client_id) REFERENCES clients(client_id),
    FOREIGN KEY (landlord_client_id) REFERENCES clients(client_id),
    FOREIGN KEY (listing_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (tenant_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (created_by) REFERENCES employees(employee_id),
    
    CHECK (lease_end_date > lease_start_date),
    CHECK (approval_date IS NULL OR approval_date >= application_date),
    CHECK (move_in_date IS NULL OR move_in_date >= lease_start_date),
    CHECK (move_out_date IS NULL OR move_out_date <= lease_end_date OR early_termination = TRUE)
);

-- =============================================================================
-- ADVANCED COMMISSION AND FINANCIAL MANAGEMENT
-- =============================================================================

-- Enhanced commission tracking with configurable rates
CREATE TABLE commissions (
    commission_id SERIAL PRIMARY KEY,
    agent_id INTEGER NOT NULL,
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('Sale', 'Rental')),
    sales_transaction_id INTEGER,
    rental_transaction_id INTEGER,
    
    -- Commission Calculation
    transaction_amount DECIMAL(12,2) NOT NULL CHECK (transaction_amount > 0),
    commission_rate DECIMAL(5,4) NOT NULL CHECK (commission_rate >= 0 AND commission_rate <= 1),
    gross_commission DECIMAL(10,2) NOT NULL CHECK (gross_commission >= 0),
    
    -- Commission Splits
    office_split_percentage DECIMAL(5,4) NOT NULL CHECK (office_split_percentage >= 0 AND office_split_percentage <= 1),
    office_split_amount DECIMAL(10,2) NOT NULL CHECK (office_split_amount >= 0),
    agent_split_percentage DECIMAL(5,4) GENERATED ALWAYS AS (1 - office_split_percentage) STORED,
    agent_commission DECIMAL(10,2) NOT NULL CHECK (agent_commission >= 0),
    
    -- Additional Splits
    referral_commission DECIMAL(8,2) DEFAULT 0 CHECK (referral_commission >= 0),
    referral_agent_id INTEGER,
    team_split_amount DECIMAL(8,2) DEFAULT 0 CHECK (team_split_amount >= 0),
    mentor_split_amount DECIMAL(8,2) DEFAULT 0 CHECK (mentor_split_amount >= 0),
    
    -- Deductions
    marketing_fee DECIMAL(8,2) DEFAULT 0 CHECK (marketing_fee >= 0),
    franchise_fee DECIMAL(8,2) DEFAULT 0 CHECK (franchise_fee >= 0),
    transaction_fee DECIMAL(8,2) DEFAULT 0 CHECK (transaction_fee >= 0),
    other_deductions DECIMAL(8,2) DEFAULT 0 CHECK (other_deductions >= 0),
    total_deductions DECIMAL(8,2) GENERATED ALWAYS AS (
        marketing_fee + franchise_fee + transaction_fee + other_deductions
    ) STORED,
    
    -- Final Amounts
    net_agent_commission DECIMAL(10,2) GENERATED ALWAYS AS (
        agent_commission - total_deductions - referral_commission - team_split_amount - mentor_split_amount
    ) STORED,
    
    -- Payment Information
    payment_status VARCHAR(20) NOT NULL DEFAULT 'Pending' 
        CHECK (payment_status IN ('Pending', 'Approved', 'Paid', 'Hold', 'Disputed', 'Reversed')),
    hold_reason VARCHAR(200),
    payment_date DATE,
    payment_method VARCHAR(30) CHECK (payment_method IN ('Direct Deposit', 'Check', 'Wire Transfer', 'Other')),
    payment_reference VARCHAR(100),
    
    -- Tax Information
    tax_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    tax_form_sent BOOLEAN DEFAULT FALSE,
    tax_form_type VARCHAR(20),
    
    -- Commission Notes
    commission_notes TEXT,
    calculation_notes TEXT,
    
    -- System Fields
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    calculated_by INTEGER NOT NULL,
    approved_by INTEGER,
    approved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (sales_transaction_id) REFERENCES sales_transactions(transaction_id),
    FOREIGN KEY (rental_transaction_id) REFERENCES rental_transactions(rental_transaction_id),
    FOREIGN KEY (referral_agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (calculated_by) REFERENCES employees(employee_id),
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id),
    
    CHECK ((sales_transaction_id IS NOT NULL) XOR (rental_transaction_id IS NOT NULL)),
    CHECK (gross_commission = office_split_amount + agent_commission),
    CHECK (net_agent_commission >= 0)
);

-- Office financial tracking with detailed categorization
CREATE TABLE office_finances (
    finance_id SERIAL PRIMARY KEY,
    office_id INTEGER NOT NULL,
    
    -- Transaction Details
    transaction_date DATE NOT NULL,
    fiscal_quarter INTEGER GENERATED ALWAYS AS (EXTRACT(QUARTER FROM transaction_date)) STORED,
    fiscal_year INTEGER GENERATED ALWAYS AS (EXTRACT(YEAR FROM transaction_date)) STORED,
    fiscal_month INTEGER GENERATED ALWAYS AS (EXTRACT(MONTH FROM transaction_date)) STORED,
    
    -- Transaction Classification
    transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('Revenue', 'Expense', 'Transfer')),
    category VARCHAR(50) NOT NULL,
    subcategory VARCHAR(50),
    amount DECIMAL(10,2) NOT NULL CHECK (amount != 0),
    
    -- References
    reference_transaction_id INTEGER,
    reference_type VARCHAR(20) CHECK (reference_type IN ('Sale', 'Rental', 'Commission', 'Marketing', 'Operating', 'Other')),
    commission_id INTEGER,
    
    -- Financial Details
    account_code VARCHAR(20),
    description TEXT NOT NULL,
    payment_method VARCHAR(30),
    vendor_company VARCHAR(100),
    receipt_number VARCHAR(50),
    invoice_number VARCHAR(50),
    
    -- Approval and Processing
    approval_required BOOLEAN DEFAULT FALSE,
    approved_by INTEGER,
    approved_at TIMESTAMP,
    processed_by INTEGER NOT NULL,
    
    -- Tax and Accounting
    tax_deductible BOOLEAN DEFAULT FALSE,
    tax_category VARCHAR(50),
    depreciation_applicable BOOLEAN DEFAULT FALSE,
    asset_category VARCHAR(50),
    
    -- System Fields
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (office_id) REFERENCES offices(office_id),
    FOREIGN KEY (commission_id) REFERENCES commissions(commission_id),
    FOREIGN KEY (approved_by) REFERENCES employees(employee_id),
    FOREIGN KEY (processed_by) REFERENCES employees(employee_id)
);

-- =============================================================================
-- ANALYTICS AND FEEDBACK SYSTEMS
-- =============================================================================

-- Comprehensive client feedback system
CREATE TABLE client_feedback (
    feedback_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL,
    agent_id INTEGER NOT NULL,
    
    -- Feedback Context
    feedback_type VARCHAR(30) NOT NULL CHECK (feedback_type IN ('Appointment', 'Open House', 'Transaction', 'General Service', 'Communication', 'Follow-up')),
    related_appointment_id INTEGER,
    related_open_house_id INTEGER,
    related_sales_transaction_id INTEGER,
    related_rental_transaction_id INTEGER,
    
    -- Ratings (1-5 scale)
    overall_rating INTEGER NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),
    communication_rating INTEGER CHECK (communication_rating IS NULL OR (communication_rating >= 1 AND communication_rating <= 5)),
    professionalism_rating INTEGER CHECK (professionalism_rating IS NULL OR (professionalism_rating >= 1 AND professionalism_rating <= 5)),
    knowledge_rating INTEGER CHECK (knowledge_rating IS NULL OR (knowledge_rating >= 1 AND knowledge_rating <= 5)),
    responsiveness_rating INTEGER CHECK (responsiveness_rating IS NULL OR (responsiveness_rating >= 1 AND responsiveness_rating <= 5)),
    negotiation_rating INTEGER CHECK (negotiation_rating IS NULL OR (negotiation_rating >= 1 AND negotiation_rating <= 5)),
    availability_rating INTEGER CHECK (availability_rating IS NULL OR (availability_rating >= 1 AND availability_rating <= 5)),
    
    -- Detailed Feedback
    positive_feedback TEXT,
    negative_feedback TEXT,
    suggestions TEXT,
    written_feedback TEXT,
    
    -- Recommendations and Referrals
    would_recommend BOOLEAN,
    likelihood_to_refer INTEGER CHECK (likelihood_to_refer IS NULL OR (likelihood_to_refer >= 1 AND likelihood_to_refer <= 10)),
    has_referred BOOLEAN DEFAULT FALSE,
    referral_count INTEGER DEFAULT 0 CHECK (referral_count >= 0),
    
    -- Feedback Management
    feedback_date DATE NOT NULL DEFAULT CURRENT_DATE,
    feedback_method VARCHAR(30) CHECK (feedback_method IN ('Online Survey', 'Phone Call', 'Email', 'In-Person', 'Text', 'Mail')),
    is_verified BOOLEAN DEFAULT TRUE,
    is_published BOOLEAN DEFAULT FALSE,
    publish_approval_required BOOLEAN DEFAULT TRUE,
    approved_for_marketing BOOLEAN DEFAULT FALSE,
    
    -- Response and Follow-up
    agent_response TEXT,
    agent_response_date DATE,
    follow_up_required BOOLEAN DEFAULT FALSE,
    follow_up_completed BOOLEAN DEFAULT FALSE,
    issue_resolved BOOLEAN DEFAULT TRUE,
    
    -- System Fields
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (client_id) REFERENCES clients(client_id),
    FOREIGN KEY (agent_id) REFERENCES agents(agent_id),
    FOREIGN KEY (related_appointment_id) REFERENCES appointments(appointment_id),
    FOREIGN KEY (related_open_house_id) REFERENCES open_houses(open_house_id),
    FOREIGN KEY (related_sales_transaction_id) REFERENCES sales_transactions(transaction_id),
    FOREIGN KEY (related_rental_transaction_id) REFERENCES rental_transactions(rental_transaction_id)
);

-- Advanced property analytics and tracking
CREATE TABLE property_analytics (
    analytics_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    
    -- Date Range for Analytics
    date_period DATE NOT NULL,
    period_type VARCHAR(20) NOT NULL CHECK (period_type IN ('Daily', 'Weekly', 'Monthly', 'Quarterly', 'Yearly')),
    
    -- View and Engagement Metrics
    total_views INTEGER DEFAULT 0 CHECK (total_views >= 0),
    unique_viewers INTEGER DEFAULT 0 CHECK (unique_viewers >= 0),
    online_views INTEGER DEFAULT 0 CHECK (online_views >= 0),
    mobile_views INTEGER DEFAULT 0 CHECK (mobile_views >= 0),
    photo_views INTEGER DEFAULT 0 CHECK (photo_views >= 0),
    virtual_tour_views INTEGER DEFAULT 0 CHECK (virtual_tour_views >= 0),
    
    -- Showing and Appointment Metrics
    total_showings INTEGER DEFAULT 0 CHECK (total_showings >= 0),
    private_showings INTEGER DEFAULT 0 CHECK (private_showings >= 0),
    open_house_attendance INTEGER DEFAULT 0 CHECK (open_house_attendance >= 0),
    broker_showings INTEGER DEFAULT 0 CHECK (broker_showings >= 0),
    
    -- Inquiry and Lead Metrics
    total_inquiries INTEGER DEFAULT 0 CHECK (total_inquiries >= 0),
    phone_inquiries INTEGER DEFAULT 0 CHECK (phone_inquiries >= 0),
    email_inquiries INTEGER DEFAULT 0 CHECK (email_inquiries >= 0),
    qualified_leads INTEGER DEFAULT 0 CHECK (qualified_leads >= 0),
    
    -- Engagement Quality
    average_time_on_listing INTEGER CHECK (average_time_on_listing IS NULL OR average_time_on_listing >= 0),
    bounce_rate DECIMAL(5,2) CHECK (bounce_rate IS NULL OR (bounce_rate >= 0 AND bounce_rate <= 100)),
    return_visitor_rate DECIMAL(5,2) CHECK (return_visitor_rate IS NULL OR (return_visitor_rate >= 0 AND return_visitor_rate <= 100)),
    
    -- Market Position
    comparable_properties_count INTEGER DEFAULT 0 CHECK (comparable_properties_count >= 0),
    price_rank_in_area INTEGER CHECK (price_rank_in_area IS NULL OR price_rank_in_area > 0),
    days_on_market_rank INTEGER CHECK (days_on_market_rank IS NULL OR days_on_market_rank > 0),
    
    -- Performance Indicators
    listing_performance_score DECIMAL(5,2) CHECK (listing_performance_score IS NULL OR (listing_performance_score >= 0 AND listing_performance_score <= 100)),
    market_competitiveness DECIMAL(5,2) CHECK (market_competitiveness IS NULL OR (market_competitiveness >= 0 AND market_competitiveness <= 100)),
    
    -- System Fields
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_source VARCHAR(50) DEFAULT 'Internal',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    
    UNIQUE (property_id, date_period, period_type)
);

-- Property view tracking with detailed analytics
CREATE TABLE property_views (
    view_id SERIAL PRIMARY KEY,
    property_id INTEGER NOT NULL,
    client_id INTEGER,
    
    -- View Details
    view_date DATE NOT NULL DEFAULT CURRENT_DATE,
    view_time TIME NOT NULL DEFAULT CURRENT_TIME,
    view_source VARCHAR(50) NOT NULL CHECK (view_source IN ('Website', 'Mobile App', 'Email', 'Social Media', 'Agent Portal', 'MLS', 'Third Party', 'Print Ad', 'Other')),
    device_type VARCHAR(30) CHECK (device_type IN ('Desktop', 'Mobile', 'Tablet', 'Other')),
    browser VARCHAR(50),
    operating_system VARCHAR(50),
    
    -- Engagement Metrics
    session_duration_seconds INTEGER CHECK (session_duration_seconds IS NULL OR session_duration_seconds >= 0),
    pages_viewed INTEGER DEFAULT 1 CHECK (pages_viewed >= 1),
    photos_viewed INTEGER DEFAULT 0 CHECK (photos_viewed >= 0),
    videos_watched INTEGER DEFAULT 0 CHECK (videos_watched >= 0),
    virtual_tour_accessed BOOLEAN DEFAULT FALSE,
    virtual_tour_completion_percentage INTEGER CHECK (virtual_tour_completion_percentage IS NULL OR (virtual_tour_completion_percentage >= 0 AND virtual_tour_completion_percentage <= 100)),
    
    -- Actions Taken
    contact_form_submitted BOOLEAN DEFAULT FALSE,
    showing_requested BOOLEAN DEFAULT FALSE,
    phone_number_clicked BOOLEAN DEFAULT FALSE,
    email_clicked BOOLEAN DEFAULT FALSE,
    saved_property BOOLEAN DEFAULT FALSE,
    shared_property BOOLEAN DEFAULT FALSE,
    
    -- Geographic and Technical Data
    user_ip_address INET,
    user_location_city VARCHAR(100),
    user_location_state VARCHAR(50),
    user_agent TEXT,
    referrer_url VARCHAR(500),
    
    -- Lead Quality Indicators
    is_return_visitor BOOLEAN DEFAULT FALSE,
    visit_sequence_number INTEGER DEFAULT 1 CHECK (visit_sequence_number >= 1),
    lead_score INTEGER CHECK (lead_score IS NULL OR (lead_score >= 0 AND lead_score <= 100)),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE,
    FOREIGN KEY (client_id) REFERENCES clients(client_id)
);

-- =============================================================================
-- ADVANCED TRIGGERS AND AUTOMATION
-- =============================================================================

-- Enhanced timestamp update function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers to all relevant tables
CREATE TRIGGER update_offices_updated_at BEFORE UPDATE ON offices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_agents_updated_at BEFORE UPDATE ON agents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clients_updated_at BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_client_preferences_updated_at BEFORE UPDATE ON client_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_neighborhoods_updated_at BEFORE UPDATE ON neighborhoods
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_schools_updated_at BEFORE UPDATE ON schools
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_properties_updated_at BEFORE UPDATE ON properties
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_appointments_updated_at BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_open_houses_updated_at BEFORE UPDATE ON open_houses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sales_transactions_updated_at BEFORE UPDATE ON sales_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rental_transactions_updated_at BEFORE UPDATE ON rental_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_commissions_updated_at BEFORE UPDATE ON commissions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Advanced commission calculation with configurable rates
CREATE OR REPLACE FUNCTION calculate_commission_advanced()
RETURNS TRIGGER AS $$
DECLARE
    commission_config RECORD;
    calculated_rate DECIMAL(5,4);
    calculated_split DECIMAL(5,4);
BEGIN
    -- For sales transactions
    IF TG_TABLE_NAME = 'sales_transactions' AND NEW.transaction_status = 'Closed' THEN
        -- Get commission rate configuration
        SELECT * INTO commission_config 
        FROM commission_rates 
        WHERE transaction_type = 'Sale' 
          AND property_type = (SELECT property_type FROM properties WHERE property_id = NEW.property_id)
          AND (min_amount <= NEW.sale_price AND (max_amount IS NULL OR max_amount >= NEW.sale_price))
          AND is_active = TRUE 
          AND effective_date <= CURRENT_DATE 
          AND (expiry_date IS NULL OR expiry_date > CURRENT_DATE)
        ORDER BY effective_date DESC 
        LIMIT 1;
        
        -- Use default rate if no configuration found
        calculated_rate := COALESCE(commission_config.commission_rate, 0.03);
        calculated_split := COALESCE(commission_config.office_split_rate, 0.5);
        
        -- Update agent totals
        UPDATE agents 
        SET total_sales_volume = total_sales_volume + NEW.sale_price,
            total_sales_count = total_sales_count + 1,
            ytd_sales_volume = CASE 
                WHEN EXTRACT(YEAR FROM CURRENT_DATE) = EXTRACT(YEAR FROM NEW.actual_closing_date)
                THEN ytd_sales_volume + NEW.sale_price
                ELSE ytd_sales_volume
            END
        WHERE agent_id = NEW.listing_agent_id;
        
        -- Create commission record for listing agent
        INSERT INTO commissions (
            agent_id, transaction_type, sales_transaction_id, 
            transaction_amount, commission_rate, gross_commission, 
            office_split_percentage, office_split_amount, agent_commission,
            calculated_by
        )
        VALUES (
            NEW.listing_agent_id,
            'Sale',
            NEW.transaction_id,
            NEW.sale_price,
            calculated_rate,
            NEW.sale_price * calculated_rate,
            calculated_split,
            (NEW.sale_price * calculated_rate) * calculated_split,
            (NEW.sale_price * calculated_rate) * (1 - calculated_split),
            NEW.created_by
        );
        
        -- Create commission for buyer agent if different
        IF NEW.buyer_agent_id IS NOT NULL AND NEW.buyer_agent_id != NEW.listing_agent_id THEN
            INSERT INTO commissions (
                agent_id, transaction_type, sales_transaction_id, 
                transaction_amount, commission_rate, gross_commission, 
                office_split_percentage, office_split_amount, agent_commission,
                calculated_by
            )
            VALUES (
                NEW.buyer_agent_id,
                'Sale',
                NEW.transaction_id,
                NEW.sale_price,
                calculated_rate,
                NEW.sale_price * calculated_rate,
                calculated_split,
                (NEW.sale_price * calculated_rate) * calculated_split,
                (NEW.sale_price * calculated_rate) * (1 - calculated_split),
                NEW.created_by
            );
        END IF;
    END IF;
    
    -- For rental transactions
    IF TG_TABLE_NAME = 'rental_transactions' AND NEW.rental_status = 'Active' THEN
        -- Get rental commission configuration
        SELECT * INTO commission_config 
        FROM commission_rates 
        WHERE transaction_type = 'Rental' 
          AND property_type = (SELECT property_type FROM properties WHERE property_id = NEW.property_id)
          AND is_active = TRUE 
          AND effective_date <= CURRENT_DATE 
          AND (expiry_date IS NULL OR expiry_date > CURRENT_DATE)
        ORDER BY effective_date DESC 
        LIMIT 1;
        
        calculated_rate := COALESCE(commission_config.commission_rate, 0.08);
        calculated_split := COALESCE(commission_config.office_split_rate, 0.5);
        
        -- Update agent totals
        UPDATE agents 
        SET total_rental_volume = total_rental_volume + NEW.annual_rent_amount,
            total_rental_count = total_rental_count + 1,
            ytd_rental_volume = CASE 
                WHEN EXTRACT(YEAR FROM CURRENT_DATE) = EXTRACT(YEAR FROM NEW.lease_start_date)
                THEN ytd_rental_volume + NEW.annual_rent_amount
                ELSE ytd_rental_volume
            END
        WHERE agent_id = NEW.listing_agent_id;
        
        -- Create commission record (typically one month rent)
        INSERT INTO commissions (
            agent_id, transaction_type, rental_transaction_id,
            transaction_amount, commission_rate, gross_commission, 
            office_split_percentage, office_split_amount, agent_commission,
            calculated_by
        )
        VALUES (
            NEW.listing_agent_id,
            'Rental',
            NEW.rental_transaction_id,
            NEW.monthly_rent,
            calculated_rate,
            NEW.monthly_rent * calculated_rate,
            calculated_split,
            (NEW.monthly_rent * calculated_rate) * calculated_split,
            (NEW.monthly_rent * calculated_rate) * (1 - calculated_split),
            NEW.created_by
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply commission triggers
CREATE TRIGGER sales_commission_trigger
    AFTER INSERT OR UPDATE OF transaction_status ON sales_transactions
    FOR EACH ROW EXECUTE FUNCTION calculate_commission_advanced();

CREATE TRIGGER rental_commission_trigger
    AFTER INSERT OR UPDATE OF rental_status ON rental_transactions
    FOR EACH ROW EXECUTE FUNCTION calculate_commission_advanced();

-- Property status update with validation
CREATE OR REPLACE FUNCTION update_property_status_advanced()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate status transition
    IF NOT EXISTS (
        SELECT 1 FROM property_status_transitions 
        WHERE from_status = OLD.listing_status 
          AND to_status = NEW.listing_status 
          AND is_allowed = TRUE
    ) THEN
        RAISE EXCEPTION 'Status change from % to % is not allowed', OLD.listing_status, NEW.listing_status;
    END IF;
    
    -- Update status change date
    IF OLD.listing_status != NEW.listing_status THEN
        NEW.previous_status := OLD.listing_status;
        NEW.status_change_date := CURRENT_DATE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER property_status_validation_trigger
    BEFORE UPDATE OF listing_status ON properties
    FOR EACH ROW EXECUTE FUNCTION update_property_status_advanced();

-- Automatic property status updates from transactions
CREATE OR REPLACE FUNCTION update_property_from_transaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Update property status when sold
    IF TG_TABLE_NAME = 'sales_transactions' AND NEW.transaction_status = 'Closed' THEN
        UPDATE properties 
        SET listing_status = 'Sold',
            previous_status = listing_status,
            status_change_date = CURRENT_DATE
        WHERE property_id = NEW.property_id;
    END IF;
    
    -- Update property status when rented
    IF TG_TABLE_NAME = 'rental_transactions' AND NEW.rental_status = 'Active' THEN
        UPDATE properties 
        SET listing_status = 'Rented',
            previous_status = listing_status,
            status_change_date = CURRENT_DATE
        WHERE property_id = NEW.property_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply property update triggers
CREATE TRIGGER update_property_status_sale
    AFTER UPDATE OF transaction_status ON sales_transactions
    FOR EACH ROW EXECUTE FUNCTION update_property_from_transaction();

CREATE TRIGGER update_property_status_rental
    AFTER UPDATE OF rental_status ON rental_transactions
    FOR EACH ROW EXECUTE FUNCTION update_property_from_transaction();

-- =============================================================================
-- PERFORMANCE INDEXES (ENHANCED)
-- =============================================================================

-- Core search indexes
CREATE INDEX idx_properties_search_combined ON properties(listing_status, property_type, city, bedrooms, bathrooms, listing_price);
CREATE INDEX idx_properties_location_search ON properties(neighborhood_id, zip_code, latitude, longitude) WHERE listing_status = 'Available';
CREATE INDEX idx_properties_price_range_search ON properties(listing_price, square_feet, property_type) WHERE listing_status IN ('Available', 'Under Contract');

-- Agent performance indexes
CREATE INDEX idx_agents_performance ON agents(total_sales_volume DESC, total_rental_volume DESC, client_satisfaction_rating DESC);
CREATE INDEX idx_agents_office_active ON agents(agent_id) INCLUDE (total_sales_count, total_rental_count) WHERE is_accepting_clients = TRUE;

-- Transaction and appointment indexes
CREATE INDEX idx_appointments_agent_schedule ON appointments(primary_agent_id, appointment_date, start_time) WHERE appointment_status IN ('Scheduled', 'Confirmed');
CREATE INDEX idx_sales_transactions_performance ON sales_transactions(listing_agent_id, transaction_status, actual_closing_date);
CREATE INDEX idx_rental_transactions_performance ON rental_transactions(listing_agent_id, rental_status, lease_start_date);

-- Analytics and reporting indexes
CREATE INDEX idx_property_views_analytics ON property_views(property_id, view_date, view_source);
CREATE INDEX idx_commissions_payment_tracking ON commissions(agent_id, payment_status, payment_date);
CREATE INDEX idx_client_feedback_ratings ON client_feedback(agent_id, overall_rating, feedback_date);

-- Financial tracking indexes
CREATE INDEX idx_office_finances_reporting ON office_finances(office_id, fiscal_year, fiscal_quarter, transaction_type);
CREATE INDEX idx_office_finances_category ON office_finances(category, subcategory, transaction_date);

-- Geographic search optimization
CREATE INDEX idx_properties_geographic ON properties USING GIST(
    POINT(longitude, latitude)
) WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND listing_status = 'Available';

CREATE INDEX idx_neighborhoods_boundary ON neighborhoods USING GIST(boundary_coordinates) 
WHERE boundary_coordinates IS NOT NULL;

-- Full-text search indexes
CREATE INDEX idx_properties_description_search ON properties USING GIN(to_tsvector('english', 
    COALESCE(property_description, '') || ' ' || 
    COALESCE(array_to_string(amenities, ' '), '') || ' ' ||
    COALESCE(address_line1, '') || ' ' ||
    COALESCE(city, '')
));

CREATE INDEX idx_clients_name_search ON clients USING GIN(to_tsvector('english', 
    first_name || ' ' || last_name || ' ' || COALESCE(preferred_name, '')
));

-- =============================================================================
-- BUSINESS INTELLIGENCE VIEWS (ENHANCED)
-- =============================================================================

-- Comprehensive agent performance view
CREATE VIEW agent_performance_dashboard AS
SELECT 
    a.agent_id,
    e.first_name || ' ' || e.last_name AS agent_name,
    e.office_id,
    o.office_name,
    
    -- Current Year Performance
    a.ytd_sales_volume,
    a.ytd_rental_volume,
    a.total_sales_count,
    a.total_rental_count,
    
    -- Lifetime Performance
    a.total_sales_volume,
    a.total_rental_volume,
    
    -- Recent Activity (Last 30 days)
    COALESCE(recent.recent_sales_count, 0) AS sales_last_30_days,
    COALESCE(recent.recent_rental_count, 0) AS rentals_last_30_days,
    COALESCE(recent.recent_appointments, 0) AS appointments_last_30_days,
    
    -- Client Satisfaction
    a.client_satisfaction_rating,
    COALESCE(feedback_stats.total_feedback_count, 0) AS total_feedback_count,
    COALESCE(feedback_stats.avg_rating_last_90_days, 0) AS recent_avg_rating,
    
    -- Commission Information
    COALESCE(commission_stats.ytd_commission, 0) AS ytd_commission_earned,
    COALESCE(commission_stats.pending_commission, 0) AS pending_commission,
    
    -- Activity Metrics
    COALESCE(activity_stats.active_listings, 0) AS active_listings,
    COALESCE(activity_stats.active_clients, 0) AS active_clients,
    
    -- Performance Indicators
    CASE 
        WHEN a.total_sales_count + a.total_rental_count = 0 THEN 'New Agent'
        WHEN a.client_satisfaction_rating >= 4.5 AND a.ytd_sales_volume > 1000000 THEN 'Top Performer'
        WHEN a.client_satisfaction_rating >= 4.0 AND a.ytd_sales_volume > 500000 THEN 'High Performer'
        WHEN a.client_satisfaction_rating >= 3.5 THEN 'Good Performer'
        ELSE 'Needs Improvement'
    END AS performance_category

FROM agents a
JOIN employees e ON a.agent_id = e.employee_id
JOIN offices o ON e.office_id = o.office_id

-- Recent activity subquery
LEFT JOIN (
    SELECT 
        listing_agent_id,
        COUNT(CASE WHEN transaction_status = 'Closed' AND actual_closing_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS recent_sales_count,
        0 AS recent_rental_count,
        0 AS recent_appointments
    FROM sales_transactions 
    WHERE actual_closing_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY listing_agent_id
    
    UNION ALL
    
    SELECT 
        listing_agent_id,
        0 AS recent_sales_count,
        COUNT(CASE WHEN rental_status = 'Active' AND lease_start_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS recent_rental_count,
        0 AS recent_appointments
    FROM rental_transactions 
    WHERE lease_start_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY listing_agent_id
    
    UNION ALL
    
    SELECT 
        primary_agent_id,
        0 AS recent_sales_count,
        0 AS recent_rental_count,
        COUNT(*) AS recent_appointments
    FROM appointments 
    WHERE appointment_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY primary_agent_id
) recent ON a.agent_id = recent.listing_agent_id

-- Feedback statistics
LEFT JOIN (
    SELECT 
        agent_id,
        COUNT(*) AS total_feedback_count,
        AVG(CASE WHEN feedback_date >= CURRENT_DATE - INTERVAL '90 days' THEN overall_rating END) AS avg_rating_last_90_days
    FROM client_feedback 
    GROUP BY agent_id
) feedback_stats ON a.agent_id = feedback_stats.agent_id

-- Commission statistics
LEFT JOIN (
    SELECT 
        agent_id,
        SUM(CASE WHEN payment_status = 'Paid' AND EXTRACT(YEAR FROM payment_date) = EXTRACT(YEAR FROM CURRENT_DATE) THEN net_agent_commission ELSE 0 END) AS ytd_commission,
        SUM(CASE WHEN payment_status IN ('Pending', 'Approved') THEN net_agent_commission ELSE 0 END) AS pending_commission
    FROM commissions 
    GROUP BY agent_id
) commission_stats ON a.agent_id = commission_stats.agent_id

-- Activity statistics
LEFT JOIN (
    SELECT 
        listing_agent_id,
        COUNT(CASE WHEN listing_status = 'Available' THEN 1 END) AS active_listings,
        COUNT(DISTINCT CASE WHEN client_status = 'Active' THEN primary_agent_id END) AS active_clients
    FROM properties p
    LEFT JOIN clients c ON p.listing_agent_id = c.primary_agent_id
    GROUP BY listing_agent_id
) activity_stats ON a.agent_id = activity_stats.listing_agent_id

WHERE e.is_active = TRUE;

-- Property market analysis view
CREATE VIEW property_market_analysis AS
SELECT 
    p.property_id,
    p.property_type,
    p.city,
    p.neighborhood_id,
    n.neighborhood_name,
    p.listing_price,
    p.price_per_sqft,
    p.bedrooms,
    p.bathrooms,
    p.square_feet,
    p.listing_status,
    p.days_on_market,
    
    -- Market Position
    RANK() OVER (PARTITION BY p.neighborhood_id, p.property_type ORDER BY p.listing_price) AS price_rank_in_area,
    RANK() OVER (PARTITION BY p.neighborhood_id, p.property_type ORDER BY p.days_on_market DESC) AS days_on_market_rank,
    
    -- Comparative Analysis
    AVG(comp.listing_price) OVER (PARTITION BY p.neighborhood_id, p.property_type) AS avg_price_in_area,
    AVG(comp.price_per_sqft) OVER (PARTITION BY p.neighborhood_id, p.property_type) AS avg_price_per_sqft_in_area,
    AVG(comp.days_on_market) OVER (PARTITION BY p.neighborhood_id, p.property_type) AS avg_days_on_market_in_area,
    COUNT(*) OVER (PARTITION BY p.neighborhood_id, p.property_type) AS comparable_properties_count,
    
    -- Performance Metrics
    COALESCE(analytics.total_views, 0) AS total_views_30_days,
    COALESCE(analytics.total_showings, 0) AS total_showings_30_days,
    COALESCE(analytics.total_inquiries, 0) AS total_inquiries_30_days,
    
    -- Price Analysis
    CASE 
        WHEN p.listing_price > AVG(comp.listing_price) OVER (PARTITION BY p.neighborhood_id, p.property_type) * 1.1 THEN 'Above Market'
        WHEN p.listing_price < AVG(comp.listing_price) OVER (PARTITION BY p.neighborhood_id, p.property_type) * 0.9 THEN 'Below Market'
        ELSE 'Market Rate'
    END AS price_category,
    
    -- Market Competitiveness Score
    LEAST(100, GREATEST(0, 
        50 + 
        (CASE WHEN p.days_on_market < 30 THEN 20 ELSE -10 END) +
        (CASE WHEN COALESCE(analytics.total_views, 0) > 50 THEN 15 ELSE -5 END) +
        (CASE WHEN COALESCE(analytics.total_showings, 0) > 5 THEN 15 ELSE -5 END)
    )) AS competitiveness_score

FROM properties p
LEFT JOIN neighborhoods n ON p.neighborhood_id = n.neighborhood_id
LEFT JOIN properties comp ON p.neighborhood_id = comp.neighborhood_id 
    AND p.property_type = comp.property_type 
    AND comp.listing_status IN ('Available', 'Under Contract', 'Sold', 'Rented')
    AND comp.listing_date >= CURRENT_DATE - INTERVAL '6 months'

-- Analytics for last 30 days
LEFT JOIN (
    SELECT 
        property_id,
        COUNT(DISTINCT pv.view_id) AS total_views,
        COUNT(DISTINCT ps.showing_id) AS total_showings,
        COUNT(DISTINCT a.appointment_id) AS total_inquiries
    FROM properties prop
    LEFT JOIN property_views pv ON prop.property_id = pv.property_id 
        AND pv.view_date >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN property_showings ps ON prop.property_id = ps.property_id 
        AND ps.scheduled_date >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN appointments a ON prop.property_id = a.property_id 
        AND a.appointment_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY property_id
) analytics ON p.property_id = analytics.property_id

WHERE p.listing_date >= CURRENT_DATE - INTERVAL '1 year';

-- =============================================================================
-- INITIAL DATA SETUP
-- =============================================================================

-- Insert default commission rates
INSERT INTO commission_rates (transaction_type, property_type, commission_rate, office_split_rate) VALUES
('Sale', 'House', 0.06, 0.5),
('Sale', 'Condo', 0.06, 0.5),
('Sale', 'Townhouse', 0.06, 0.5),
('Sale', 'Apartment', 0.06, 0.5),
('Sale', 'Loft', 0.06, 0.5),
('Rental', 'House', 0.12, 0.5),
('Rental', 'Condo', 0.12, 0.5),
('Rental', 'Townhouse', 0.12, 0.5),
('Rental', 'Apartment', 0.15, 0.5),
('Rental', 'Loft', 0.15, 0.5);

-- Insert property status transitions
INSERT INTO property_status_transitions (from_status, to_status, is_allowed) VALUES
('Available', 'Under Contract', TRUE),
('Available', 'Off Market', TRUE),
('Available', 'Withdrawn', TRUE),
('Under Contract', 'Sold', TRUE),
('Under Contract', 'Rented', TRUE),
('Under Contract', 'Available', TRUE),
('Under Contract', 'Cancelled', TRUE),
('Sold', 'Available', FALSE),
('Rented', 'Available', TRUE),
('Off Market', 'Available', TRUE),
('Withdrawn', 'Available', TRUE),
('Coming Soon', 'Available', TRUE);

-- =============================================================================
-- COMPLETION AND SUMMARY
-- =============================================================================

/*
CORRECTED DATABASE SCHEMA SUMMARY (Version 2.0):

✅ FIXED ISSUES:
1. Circular Reference Problem - Resolved with deferred constraints
2. Commission Calculation - Now uses configurable rates from commission_rates table
3. Business Constraints - Added comprehensive check constraints and validation
4. Property Status Logic - Implemented proper state transition validation
5. Performance Optimization - Enhanced indexes for real estate search patterns
6. Data Type Consistency - Standardized phone, email, and numeric validations
7. Missing Business Requirements - Added all required tables and functionality

✅ KEY IMPROVEMENTS:
- 25+ normalized tables in 3NF
- Configurable commission system
- Advanced property analytics
- Comprehensive client feedback system
- Geographic search capabilities
- Full audit trail and compliance features
- Role-based security model
- Automated business logic with triggers
- Performance-optimized indexes
- Business intelligence views

✅ BUSINESS REQUIREMENTS COVERAGE:
- ✓ Office and employee management
- ✓ Client relationship management with preferences
- ✓ Property inventory with rich metadata
- ✓ Appointment and event scheduling
- ✓ Transaction processing (sales & rentals)
- ✓ Commission automation with configurable rates
- ✓ Financial tracking and reporting
- ✓ Feedback and analytics systems
- ✓ Geographic and neighborhood data
- ✓ School district information
- ✓ Performance monitoring and dashboards
- ✓ Security and access control
- ✓ Data integrity and validation

This corrected schema addresses all identified flaws and provides a robust,
scalable foundation for Dream Homes NYC's luxury real estate operations.
*/

COMMIT; 