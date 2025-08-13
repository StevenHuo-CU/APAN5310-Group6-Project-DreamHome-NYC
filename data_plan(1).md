# Data Processing Plan for Dream Homes NYC ETL

## 1. Objective

The goal of this ETL (Extract, Transform, Load) process is to extract data from a source CSV file (`dream_homes_nyc_dataset_v8.csv`), transform it into a structured format, and load it into a PostgreSQL database. This plan outlines the data flow, transformation logic, and database table mappings.

## 2. Data Source

- **Type**: CSV File
- **Name**: `dream_homes_nyc_dataset_v8.csv`
- **Description**: Contains transactional data for a real estate company, including property listings, sales, rentals, client details, and agent information.

## 3. Data Destination

- **Type**: PostgreSQL Database
- **Name**: `dream_homes_db` (or as configured in `config.py`)
- **Description**: A relational database designed to store and manage the real estate data in a normalized structure.

## 4. ETL Process Overview

The ETL process is orchestrated by the `etl_enhanced.py` script. The process for each row in the source CSV is as follows:

1.  **Extract**: Read one row of data from the CSV file.
2.  **Transform & Load**:
    - Parse and clean data from various columns (e.g., addresses, names, monetary values).
    - Map categorical data to corresponding `enum` types or foreign keys in the database (e.g., property types, transaction statuses).
    - Insert or update records across multiple database tables in a specific order to maintain referential integrity.
    - Each main entity (like Property, Transaction) is processed, and then its related sub-entities (like Appointments, Documents, etc.) are handled.
    - The process uses separate, smaller transactions for non-critical related data to prevent a single failure from halting the entire row's import.

## 5. Data Mapping and Transformation Details

This section details how data from the source CSV is mapped to each database table.

### Table: `Office`

-   **Logic**: `insert_or_get_office` function.
-   **Description**: Inserts a new office record if it doesn't already exist based on `office_name`. Otherwise, it retrieves the existing `office_id`.
-   **Source Columns**:
    -   `listing_office_name` -> `office_name`
    -   `listing_office_address` -> Parsed into `address`, `city`, `state`, `zip_code`.
    -   `listing_office_phone` -> `phone`

### Table: `Employee`

-   **Logic**: `insert_or_get_employee` function.
-   **Description**: Handles both listing and selling agents. Inserts a new employee if one with the given email doesn't exist.
-   **Source Columns**:
    -   `listing_agent_name` / `selling_agent_name` -> Parsed into `first_name`, `last_name`.
    -   `listing_agent_email` / `selling_agent_email` -> `email`
    -   `listing_agent_phone` / `selling_agent_phone` -> `phone`
    -   `listing_agent_commission_rate` -> `commission_rate`

### Table: `Client` & `ClientRole`

-   **Logic**: `insert_or_get_client` function.
-   **Description**: Parses buyer/renter and seller/landlord information. A `ClientRole` (`buyer`, `seller`, `renter`, or `landlord`) is assigned based on the transaction type.
-   **Source Columns**:
    -   `client_buyer_info` / `client_seller_info` -> Parsed for `full_name`, `notes` (profession).
    -   `client_contact_details` -> Parsed for `email`, `phone`.

### Table: `PropertyType`

-   **Logic**: `insert_or_get_property_type` function.
-   **Description**: Maps abbreviated property types to full names (e.g., 'TH' to 'Townhouse').
-   **Source Columns**:
    -   `property_type` -> `type_name`

### Table: `Property`

-   **Description**: The central table for property listings.
-   **Source Columns**:
    -   `mls_listing_number` -> `mls_number` (Unique Key)
    -   `property_address_full` -> Parsed into `address`, `city`, `state`, `zip_code`.
    -   `bed_bath_info` -> Parsed into `bedrooms`, `bathrooms`.
    -   `list_price` -> `list_price`
    -   `square_feet` -> `square_footage`
    -   `status_current` -> Mapped to `current_status` (`active`, `sold`, etc.).
    -   `listing_date` -> `date_listed`

### Table: `PropertyFeature`

-   **Description**: Stores property amenities.
-   **Source Columns**:
    -   `property_features_list` -> Split into individual features and inserted as separate rows.

### Table: `Transaction`

-   **Description**: Records the details of a sale or rental transaction.
-   **Source Columns**:
    -   `transaction_id` -> `transaction_code` (Unique Key)
    -   `transaction_type` -> `transaction_type` (`sale` or `rental`)
    -   `status_current` -> Mapped to `status` (`pending`, `completed`, etc.).
    -   `offer_date`, `accepted_date`, `closing_date` -> Date fields.
    -   `offer_amount`, `final_price` -> `offer_amount`, `transaction_amount`.

### Table: `Appointment`

-   **Logic**: `insert_appointments` function.
-   **Description**: Parses a delimited string of appointment history.
-   **Source Columns**:
    -   `appointment_history` -> Parsed into `scheduled_datetime`, `appointment_type`, `notes`, and `feedback`.

### Table: `Commission`

-   **Logic**: `insert_commission_record` function.
-   **Description**: Calculates and records commission splits for agents.
-   **Source Columns**:
    -   `commission_total` -> `total_commission_amount`
    -   `commission_split_info` -> Parsed to get `listing_agent_amount` and `selling_agent_amount`.
    -   `payout_status` -> Mapped to `payout_status`.

### Table: `Document`

-   **Logic**: `insert_documents` function.
-   **Description**: Creates records for required legal and financial documents.
-   **Source Columns**:
    -   `documents_required` -> Split into a list of documents to be inserted.
    -   `appraisal_amount` -> If present, triggers the creation of an 'Appraisal' document record.

### Table: `ClientLead`

-   **Logic**: `insert_client_leads` function.
-   **Description**: Creates a lead record from client information.
-   **Source Columns**:
    -   `client_buyer_info` -> Parsed for name and budget.
    -   `lead_source` -> Mapped to `lead_source`.
    -   The budget is used to infer `interest_type` (`buying` vs. `renting`).

### Table: `PropertyMedia`

-   **Logic**: `insert_property_media` function.
-   **Description**: Inserts default media records (a primary photo and a floor plan) for each property. File paths are standardized based on the `property_id`.

### Table: `Lease` & `PaymentRecord`

-   **Logic**: `insert_payment_records` and main processing loop.
-   **Description**: For rental transactions, a `Lease` record is created. Associated `PaymentRecord` entries for the security deposit and first month's rent are also generated.
-   **Source Columns**:
    -   `lease_start_end` -> Parsed for `lease_start_date` and `lease_end_date`.
    -   `monthly_rent` -> `monthly_rent`
    -   `security_deposit` -> `security_deposit`
    -   `lease_terms` -> `lease_terms`

### Table: `MarketingCampaign`

-   **Description**: Records marketing efforts for a property.
-   **Source Columns**:
    -   `campaign_type` -> Mapped to `campaign_type`.
    -   `marketing_spend` -> `budget`, `actual_cost`.
    -   `listing_date` -> `start_date`.
