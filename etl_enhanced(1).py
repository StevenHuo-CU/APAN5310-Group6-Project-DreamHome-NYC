#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
import logging
import re
from datetime import datetime, timedelta
import json
from decimal import Decimal

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class EnhancedDreamHomesETL:
    def __init__(self, db_config):
        """
        Initializes the enhanced ETL class.
        """
        self.db_config = db_config
        self.conn = None
        self.cursor = None
        
    def connect_db(self):
        """Connects to the database."""
        try:
            self.conn = psycopg2.connect(**self.db_config)
            self.cursor = self.conn.cursor(cursor_factory=RealDictCursor)
            logger.info("Database connection successful.")
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise
    
    def close_db(self):
        """Closes the database connection."""
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
        logger.info("Database connection closed.")
    
    # Reuse existing mapping and parsing functions
    def parse_bed_bath_info(self, bed_bath_str):
        """Parses bed/bath information."""
        if pd.isna(bed_bath_str) or not bed_bath_str:
            return None, None
        
        pattern = r'(\d+BR|Studio)/(\d+(?:\.\d+)?BA)'
        match = re.search(pattern, str(bed_bath_str))
        
        if match:
            bed_str = match.group(1)
            bath_str = match.group(2)
            
            if bed_str == "Studio":
                bedrooms = 0
            else:
                bedrooms = int(bed_str.replace('BR', ''))
            
            bathrooms = float(bath_str.replace('BA', ''))
            
            return bedrooms, bathrooms
        
        return None, None
    
    def parse_address(self, address_full):
        """Parses address information."""
        if pd.isna(address_full) or not address_full:
            return None, None, None, None
        
        parts = str(address_full).strip().split()
        
        if len(parts) >= 4:
            zip_code = parts[-1]
            state = parts[-2]
            
            city_parts = []
            address_parts = []
            found_city = False
            
            for i in range(len(parts) - 3, -1, -1):
                if not found_city and parts[i][0].isupper():
                    city_parts.insert(0, parts[i])
                    if i == 0 or not parts[i-1][0].isupper():
                        found_city = True
                elif found_city:
                    address_parts.insert(0, parts[i])
                else:
                    address_parts.insert(0, parts[i])
            
            address = ' '.join(address_parts) if address_parts else None
            city = ' '.join(city_parts) if city_parts else None
            
            return address, city, state, zip_code
        
        return address_full, None, None, None
    
    def parse_name(self, name_str):
        """Parses a name."""
        if pd.isna(name_str) or not name_str:
            return None, None
        
        parts = str(name_str).strip().split()
        if len(parts) >= 2:
            first_name = parts[0]
            last_name = ' '.join(parts[1:])
            return first_name, last_name
        elif len(parts) == 1:
            return parts[0], ""
        return None, None
    
    def parse_client_info(self, client_info_str):
        """Parses a client information string."""
        if pd.isna(client_info_str) or not client_info_str:
            return None, None, None, None, None
        
        parts = str(client_info_str).split(' | ')
        
        name = parts[0].strip() if len(parts) > 0 else None
        profession = parts[1].strip() if len(parts) > 1 else None
        budget_info = parts[2].strip() if len(parts) > 2 else None
        notes = parts[3].strip() if len(parts) > 3 else None
        
        budget_min, budget_max = None, None
        if budget_info and 'Budget' in budget_info:
            budget_str = budget_info.replace('Budget ', '')
            if '-' in budget_str:
                try:
                    budget_parts = budget_str.split('-')
                    budget_min_str = budget_parts[0].replace('M', '').replace('K', '')
                    budget_max_str = budget_parts[1].replace('M', '').replace('K', '')
                    
                    budget_min = float(budget_min_str)
                    budget_max = float(budget_max_str)
                    
                    if 'M' in budget_parts[0]:
                        budget_min *= 1000000
                    elif 'K' in budget_parts[0]:
                        budget_min *= 1000
                    
                    if 'M' in budget_parts[1]:
                        budget_max *= 1000000
                    elif 'K' in budget_parts[1]:
                        budget_max *= 1000
                        
                except ValueError:
                    pass
        
        return name, profession, budget_min, budget_max, notes
    
    def parse_appointment_history(self, appointment_history):
        """Parses appointment history."""
        appointments = []
        if pd.isna(appointment_history) or not appointment_history:
            return appointments
        
        # Split multiple appointment records
        records = str(appointment_history).split(' | ')
        
        for record in records:
            try:
                # Format: "11/22/24 - Initial showing - With advisor - Had concerns"
                parts = record.strip().split(' - ')
                if len(parts) >= 2:
                    date_str = parts[0].strip()
                    appointment_type = parts[1].strip()
                    attendees = parts[2].strip() if len(parts) > 2 else ""
                    outcome = parts[3].strip() if len(parts) > 3 else ""
                    
                    # Parse date
                    try:
                        appointment_date = pd.to_datetime(date_str).date()
                    except:
                        continue
                    
                    # Map appointment type
                    type_mapping = {
                        'Initial showing': 'showing',
                        'Second visit': 'showing',
                        'Third viewing': 'showing',
                        'Final walkthrough': 'inspection'
                    }
                    
                    mapped_type = type_mapping.get(appointment_type, 'showing')
                    
                    appointments.append({
                        'date': appointment_date,
                        'type': mapped_type,
                        'attendees': attendees,
                        'outcome': outcome,
                        'notes': record
                    })
            except Exception as e:
                logger.warning(f"Failed to parse appointment record: {record} - {e}")
                continue
        
        return appointments
    
    def parse_commission_split(self, commission_split_info):
        """Parses commission split information."""
        if pd.isna(commission_split_info) or not commission_split_info:
            return None, None
        
        # Format: "Listing: 15525, Selling: 15525"
        parts = str(commission_split_info).split(', ')
        listing_amount = None
        selling_amount = None
        
        for part in parts:
            if 'Listing:' in part:
                try:
                    listing_amount = float(part.replace('Listing:', '').strip())
                except:
                    pass
            elif 'Selling:' in part:
                try:
                    selling_amount = float(part.replace('Selling:', '').strip())
                except:
                    pass
        
        return listing_amount, selling_amount
    
    def parse_documents_required(self, documents_required):
        """Parses the list of required documents."""
        documents = []
        if pd.isna(documents_required) or not documents_required:
            return documents
        
        # Split document list
        doc_list = str(documents_required).split(', ')
        
        # Map document types
        doc_type_mapping = {
            'Survey': 'other',
            'Title Report': 'title_report',
            'Appraisal': 'appraisal',
            'Disclosure': 'disclosure',
            'Contract': 'contract',
            'Inspection': 'inspection_report',
            'Insurance': 'insurance'
        }
        
        for doc in doc_list:
            doc = doc.strip()
            if doc:
                mapped_type = doc_type_mapping.get(doc, 'other')
                documents.append({
                    'name': doc,
                    'type': mapped_type
                })
        
        return documents
    
    def safe_decimal(self, value):
        """Safely converts a value to Decimal."""
        if pd.isna(value) or value == '':
            return None
        try:
            return Decimal(str(value))
        except:
            return None
    
    def safe_int(self, value):
        """Safely converts a value to an integer."""
        if pd.isna(value) or value == '':
            return None
        try:
            return int(float(value))
        except:
            return None
    
    def safe_date(self, value):
        """Safely converts a value to a date."""
        if pd.isna(value) or value == '':
            return None
        try:
            return pd.to_datetime(value).date()
        except:
            return None
    
    def map_lead_source(self, lead_source):
        """Maps lead source."""
        if not lead_source:
            return 'other'
        
        source_mapping = {
            'Website': 'website',
            'Social Media': 'social_media',
            'Referral': 'referral',
            'Walk-in': 'walk_in',
            'Open House': 'walk_in',
            'Direct Marketing': 'advertisement',
            'Direct Mail': 'advertisement'
        }
        
        return source_mapping.get(str(lead_source), 'other')
    
    def map_payout_status(self, payout_status):
        """Maps payout status."""
        if not payout_status:
            return 'pending'
        
        status_mapping = {
            'Pending': 'pending',
            'PAID': 'paid',
            'Approved': 'approved'
        }
        
        return status_mapping.get(str(payout_status), 'pending')
    
    # Reuse existing mapping functions
    def map_property_type(self, prop_type):
        """Maps property type."""
        type_mapping = {
            'Co-op': 'Cooperative',
            'TH': 'Townhouse', 
            'Condo': 'Condominium',
            'SFH': 'Single Family Home'
        }
        return type_mapping.get(prop_type, prop_type)
    
    def map_transaction_status(self, status):
        """Maps transaction status to property_status_enum."""
        status_mapping = {
            'SOLD': 'sold',
            'RENTED': 'rented', 
            'ACTIVE': 'active',
            'PENDING': 'pending'
        }
        return status_mapping.get(status, 'active')
    
    def map_transaction_status_enum(self, status):
        """Maps transaction status to transaction_status_enum."""
        status_mapping = {
            'SOLD': 'completed',
            'RENTED': 'completed', 
            'ACTIVE': 'pending',
            'PENDING': 'in_escrow'
        }
        return status_mapping.get(status, 'pending')
    
    def map_campaign_type(self, campaign_type):
        """Maps marketing campaign type to campaign_type_enum."""
        if not campaign_type:
            return 'online'
        
        clean_type = str(campaign_type).lower().replace(' ', '_')
        
        campaign_mapping = {
            'online_marketing': 'online',
            'social_media': 'social_media',
            'social_media_campaign': 'social_media',
            'print_advertising': 'print',
            'email_campaign': 'email',
            'direct_mail': 'direct_mail',
            'community_event': 'open_house',
            'open_house': 'open_house',
            'online': 'online',
            'print': 'print',
            'email': 'email'
        }
        
        return campaign_mapping.get(clean_type, 'online')
    
    # Reuse existing insert functions (simplified, details omitted here)
    def insert_or_get_office(self, office_name, office_address, office_phone):
        """Inserts or gets an office ID (reuses original implementation)."""
        if not office_name:
            return None
            
        address, city, state, zip_code = self.parse_address(office_address)
        
        self.cursor.execute("""
            SELECT office_id FROM Office WHERE office_name = %s
        """, (office_name,))
        
        result = self.cursor.fetchone()
        if result:
            return result['office_id']
        
        office_code = office_name.replace(' ', '').replace('Dream', 'DH').replace('Homes', '')[:10]
        
        self.cursor.execute("""
            INSERT INTO Office (office_code, office_name, address, city, state, zip_code, phone, email)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING office_id
        """, (
            office_code,
            office_name,
            address or office_address,
            city or 'New York',
            state or 'NY',
            zip_code or '10001',
            office_phone,
            f"info@{office_code.lower()}.com"
        ))
        
        return self.cursor.fetchone()['office_id']
    
    def insert_or_get_employee(self, agent_name, agent_email, agent_phone, commission_rate, office_id):
        """Inserts or gets an employee ID (reuses original implementation)."""
        if not agent_name:
            return None
            
        if agent_email:
            self.cursor.execute("""
                SELECT employee_id FROM Employee WHERE email = %s
            """, (agent_email,))
            
            result = self.cursor.fetchone()
            if result:
                return result['employee_id']
        
        first_name, last_name = self.parse_name(agent_name)
        
        self.cursor.execute("""
            INSERT INTO Employee (
                employee_code, first_name, last_name, email, phone, 
                job_title, office_id, hire_date, commission_rate
            ) VALUES (
                'TEMP', %s, %s, %s, %s, 'Agent', %s, CURRENT_DATE, %s
            )
            RETURNING employee_id
        """, (
            first_name or 'Unknown',
            last_name or 'Agent',
            agent_email or f"{first_name.lower()}@dreamhomes.com",
            agent_phone or '(000) 000-0000',
            office_id,
            commission_rate or 3.0
        ))
        
        return self.cursor.fetchone()['employee_id']
    
    def insert_or_get_client(self, client_info, contact_details, role_type):
        """Inserts or gets a client ID (reuses original implementation)."""
        if not client_info:
            return None
            
        name, profession, budget_min, budget_max, notes = self.parse_client_info(client_info)
        
        if not name:
            return None
        
        email, phone = None, None
        if contact_details:
            contact_parts = str(contact_details).split(' | ')
            if len(contact_parts) >= 2:
                email = contact_parts[0].replace(name + ': ', '')
                phone = contact_parts[1]
        
        if email:
            self.cursor.execute("""
                SELECT client_id FROM Client WHERE email = %s
            """, (email,))
            
            result = self.cursor.fetchone()
            if result:
                return result['client_id']
        
        self.cursor.execute("""
            INSERT INTO Client (
                client_type, full_name, email, phone, notes
            ) VALUES (
                'individual', %s, %s, %s, %s
            )
            RETURNING client_id
        """, (
            name,
            email or f"{name.lower().replace(' ', '.')}@email.com",
            phone or '(000) 000-0000',
            f"Profession: {profession}. {notes}" if profession else notes
        ))
        
        client_id = self.cursor.fetchone()['client_id']
        
        self.cursor.execute("""
            INSERT INTO ClientRole (client_id, role_type) 
            VALUES (%s, %s)
            ON CONFLICT (client_id, role_type) DO NOTHING
        """, (client_id, role_type))
        
        return client_id
    
    def insert_or_get_property_type(self, prop_type):
        """Inserts or gets a property type ID (reuses original implementation)."""
        mapped_type = self.map_property_type(prop_type)
        
        self.cursor.execute("""
            SELECT type_id FROM PropertyType WHERE type_name = %s
        """, (mapped_type,))
        
        result = self.cursor.fetchone()
        if result:
            return result['type_id']
        
        self.cursor.execute("""
            INSERT INTO PropertyType (type_name, description)
            VALUES (%s, %s)
            RETURNING type_id
        """, (
            mapped_type,
            f"Property type: {mapped_type}"
        ))
        
        return self.cursor.fetchone()['type_id']
    
    # New functions to handle missing tables
    def insert_appointments(self, appointment_history, agent_id, client_id, property_id):
        """Inserts appointment records."""
        appointments = self.parse_appointment_history(appointment_history)
        
        for appointment in appointments:
            try:
                self.cursor.execute("""
                    INSERT INTO Appointment (
                        agent_id, client_id, property_id, scheduled_datetime,
                        appointment_type, status, notes, feedback, created_by
                    ) VALUES (
                        %s, %s, %s, %s, %s, 'completed', %s, %s, %s
                    )
                """, (
                    agent_id,
                    client_id,
                    property_id,
                    datetime.combine(appointment['date'], datetime.min.time()),
                    appointment['type'],
                    appointment['notes'],
                    appointment['outcome'],
                    agent_id
                ))
            except Exception as e:
                logger.warning(f"Failed to insert appointment record: {e}")
    
    def insert_commission_record(self, transaction_id, commission_total, commission_split_info, 
                               payout_status, listing_agent_id, selling_agent_id):
        """Inserts a commission record."""
        if not commission_total:
            return
        
        listing_amount, selling_amount = self.parse_commission_split(commission_split_info)
        total_commission = self.safe_decimal(commission_total)
        
        # Use default split logic if no specific split is parsed
        if not listing_amount and total_commission:
            if selling_agent_id and selling_amount:
                # Has selling agent, split evenly
                listing_amount = total_commission / 2
                selling_amount = total_commission / 2
            else:
                # No selling agent, all goes to listing agent
                listing_amount = total_commission
                selling_amount = Decimal('0')
        elif not listing_amount:
            listing_amount = Decimal('0')
        
        if not selling_amount:
            selling_amount = Decimal('0')
        
        try:
            self.cursor.execute("""
                INSERT INTO Commission (
                    transaction_id, total_commission_amount, listing_agent_id, 
                    listing_agent_amount, selling_agent_id, selling_agent_amount,
                    payout_status
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (transaction_id) DO NOTHING
            """, (
                transaction_id,
                total_commission,
                listing_agent_id,
                listing_amount,
                selling_agent_id,
                selling_amount,
                self.map_payout_status(payout_status)
            ))
        except Exception as e:
            logger.warning(f"Failed to insert commission record: {e}")
    
    def insert_documents(self, documents_required, transaction_id, property_id, 
                       inspection_date, appraisal_amount, uploaded_by):
        """Inserts document records."""
        documents = self.parse_documents_required(documents_required)
        
        for doc in documents:
            try:
                self.cursor.execute("""
                    INSERT INTO Document (
                        transaction_id, property_id, document_type, document_name,
                        file_path, uploaded_by, is_required
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, true
                    )
                """, (
                    transaction_id,
                    property_id,
                    doc['type'],
                    doc['name'],
                    f"/documents/{doc['name'].lower().replace(' ', '_')}.pdf",
                    uploaded_by
                ))
            except Exception as e:
                logger.warning(f"Failed to insert document record: {e}")
        
        # Insert appraisal report (if appraisal amount exists)
        if appraisal_amount and inspection_date:
            try:
                self.cursor.execute("""
                    INSERT INTO Document (
                        transaction_id, property_id, document_type, document_name,
                        file_path, uploaded_by, is_required
                    ) VALUES (
                        %s, %s, 'appraisal', 'Property Appraisal Report',
                        %s, %s, true
                    )
                """, (
                    transaction_id,
                    property_id,
                    f"/documents/appraisal_{transaction_id}.pdf",
                    uploaded_by
                ))
            except Exception as e:
                logger.warning(f"Failed to insert appraisal document: {e}")
    
    def insert_client_leads(self, client_info, lead_source, property_id, assigned_agent_id):
        """Inserts client lead records."""
        if not client_info:
            return
        
        name, profession, budget_min, budget_max, notes = self.parse_client_info(client_info)
        
        if not name:
            return
        
        first_name, last_name = self.parse_name(name)
        
        # Determine interest type (buyer or renter based on budget)
        interest_type = 'buying'
        if budget_max and budget_max < 50000:  # Below 50k might be rental
            interest_type = 'renting'
        
        try:
            self.cursor.execute("""
                INSERT INTO ClientLead (
                    first_name, last_name, lead_source, property_id,
                    interest_type, budget_min, budget_max, 
                    assigned_agent_id, lead_status, notes
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, 'converted', %s
                )
            """, (
                first_name or 'Unknown',
                last_name or '',
                self.map_lead_source(lead_source),
                property_id,
                interest_type,
                self.safe_decimal(budget_min),
                self.safe_decimal(budget_max),
                assigned_agent_id,
                notes
            ))
        except Exception as e:
            logger.warning(f"Failed to insert client lead: {e}")
    
    def insert_property_media(self, property_id, uploaded_by):
        """Inserts default media records for a property."""
        try:
            # Insert default photo record
            self.cursor.execute("""
                INSERT INTO PropertyMedia (
                    property_id, media_type, file_url, title, 
                    is_primary, uploaded_by
                ) VALUES (
                    %s, 'photo', %s, 'Main Property Photo', true, %s
                )
            """, (
                property_id,
                f"/media/property_{property_id}/main.jpg",
                uploaded_by
            ))
            
            # Insert floor plan record
            self.cursor.execute("""
                INSERT INTO PropertyMedia (
                    property_id, media_type, file_url, title, 
                    uploaded_by
                ) VALUES (
                    %s, 'floor_plan', %s, 'Floor Plan', %s
                )
            """, (
                property_id,
                f"/media/property_{property_id}/floorplan.pdf",
                uploaded_by
            ))
        except Exception as e:
            logger.warning(f"Failed to insert property media: {e}")
    
    def insert_payment_records(self, lease_id, monthly_rent, security_deposit):
        """Inserts payment records for a lease."""
        if not monthly_rent:
            return
        
        try:
            # Insert security deposit record
            if security_deposit:
                self.cursor.execute("""
                    INSERT INTO PaymentRecord (
                        lease_id, payment_date, amount, payment_type,
                        payment_method, status, notes
                    ) VALUES (
                        %s, CURRENT_DATE, %s, 'deposit', 'bank_transfer', 'completed',
                        'Security deposit payment'
                    )
                """, (
                    lease_id,
                    self.safe_decimal(security_deposit)
                ))
            
            # Insert first month's rent record
            self.cursor.execute("""
                INSERT INTO PaymentRecord (
                    lease_id, payment_date, amount, payment_type,
                    payment_method, status, notes
                ) VALUES (
                    %s, CURRENT_DATE, %s, 'rent', 'bank_transfer', 'completed',
                    'First month rent payment'
                )
            """, (
                lease_id,
                self.safe_decimal(monthly_rent)
            ))
        except Exception as e:
            logger.warning(f"Failed to insert payment records: {e}")
    
    def process_data(self, csv_file_path):
        """Processes the CSV data and imports it into the database (enhanced version)."""
        logger.info("Starting to read CSV file...")
        df = pd.read_csv(csv_file_path)
        logger.info(f"Read {len(df)} records.")
        
        self.connect_db()
        
        try:
            processed_count = 0
            
            for index, row in df.iterrows():
                try:
                    logger.info(f"Processing record {index + 1}: {row['transaction_id']}")
                    
                    # 1. Process office information
                    office_id = self.insert_or_get_office(
                        row['listing_office_name'],
                        row['listing_office_address'], 
                        row['listing_office_phone']
                    )
                    
                    # 2. Process employee information
                    listing_agent_id = self.insert_or_get_employee(
                        row['listing_agent_name'],
                        row['listing_agent_email'],
                        row['listing_agent_phone'],
                        self.safe_decimal(row['listing_agent_commission_rate']),
                        office_id
                    )
                    
                    selling_agent_id = None
                    if pd.notna(row['selling_agent_name']):
                        selling_agent_id = self.insert_or_get_employee(
                            row['selling_agent_name'],
                            row['selling_agent_email'],
                            row['selling_agent_phone'],
                            2.5,
                            office_id
                        )
                    
                    # 3. Process client information
                    buyer_id = self.insert_or_get_client(
                        row['client_buyer_info'],
                        row['client_contact_details'],
                        'buyer' if row['transaction_type'] == 'sale' else 'renter'
                    )
                    
                    seller_id = self.insert_or_get_client(
                        row['client_seller_info'],
                        None,
                        'seller' if row['transaction_type'] == 'sale' else 'landlord'
                    )
                    
                    # 4. Process property type
                    property_type_id = self.insert_or_get_property_type(row['property_type'])
                    
                    # 5. Insert property information
                    address, city, state, zip_code = self.parse_address(row['property_address_full'])
                    bedrooms, bathrooms = self.parse_bed_bath_info(row['bed_bath_info'])
                    
                    self.cursor.execute("""
                        INSERT INTO Property (
                            mls_number, property_type_id, listing_office_id, listing_agent_id,
                            address, city, state, zip_code, list_price, square_footage,
                            bedrooms, bathrooms, current_status, date_listed
                        ) VALUES (
                            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                        )
                        ON CONFLICT (mls_number) DO UPDATE SET
                            current_status = EXCLUDED.current_status,
                            list_price = EXCLUDED.list_price
                        RETURNING property_id
                    """, (
                        row['mls_listing_number'],
                        property_type_id,
                        office_id,
                        listing_agent_id,
                        address,
                        city,
                        state,
                        zip_code,
                        self.safe_decimal(row['list_price']),
                        self.safe_int(row['square_feet']),
                        bedrooms,
                        bathrooms,
                        self.map_transaction_status(row['status_current']),
                        self.safe_date(row['listing_date'])
                    ))
                    
                    property_result = self.cursor.fetchone()
                    if property_result:
                        property_id = property_result['property_id']
                    else:
                        self.cursor.execute("""
                            SELECT property_id FROM Property WHERE mls_number = %s
                        """, (row['mls_listing_number'],))
                        property_id = self.cursor.fetchone()['property_id']
                    
                    # 6. Insert property features
                    if pd.notna(row['property_features_list']):
                        features = str(row['property_features_list']).split(', ')
                        for feature in features:
                            feature = feature.strip()
                            if feature:
                                self.cursor.execute("""
                                    INSERT INTO PropertyFeature (
                                        property_id, feature_type, feature_name
                                    ) VALUES (%s, %s, %s)
                                    ON CONFLICT DO NOTHING
                                """, (
                                    property_id,
                                    'amenity',
                                    feature
                                ))
                    
                    # 7. Insert transaction information
                    transaction_amount = self.safe_decimal(row['final_price']) or self.safe_decimal(row['offer_amount'])
                    
                    # Handle null offer_date
                    offer_date = self.safe_date(row['offer_date'])
                    if not offer_date:
                        # Use listing_date or current date if offer_date is missing
                        offer_date = self.safe_date(row['listing_date']) or datetime.now().date()
                    
                    # Handle null offer_amount
                    offer_amount = self.safe_decimal(row['offer_amount'])
                    if not offer_amount:
                        offer_amount = transaction_amount or self.safe_decimal(row['list_price'])
                    
                    transaction_id = None
                    if transaction_amount:
                        self.cursor.execute("""
                            INSERT INTO "Transaction" (
                                transaction_code, property_id, listing_agent_id, selling_agent_id,
                                buyer_id, seller_id, renter_id, landlord_id,
                                transaction_type, status, offer_date, offer_amount,
                                accepted_date, transaction_amount, closing_date
                            ) VALUES (
                                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                            )
                            ON CONFLICT (transaction_code) DO UPDATE SET
                                status = EXCLUDED.status,
                                transaction_amount = EXCLUDED.transaction_amount
                            RETURNING transaction_id
                        """, (
                            row['transaction_id'],
                            property_id,
                            listing_agent_id,
                            selling_agent_id,
                            buyer_id if row['transaction_type'] == 'sale' else None,
                            seller_id if row['transaction_type'] == 'sale' else None,
                            buyer_id if row['transaction_type'] == 'rental' else None,
                            seller_id if row['transaction_type'] == 'rental' else None,
                            row['transaction_type'],
                            self.map_transaction_status_enum(row['status_current']),
                            offer_date,
                            offer_amount,
                            self.safe_date(row['accepted_date']),
                            transaction_amount,
                            self.safe_date(row['closing_date'])
                        ))
                        
                        result = self.cursor.fetchone()
                        if result:
                            transaction_id = result['transaction_id']
                        else:
                            self.cursor.execute("""
                                SELECT transaction_id FROM "Transaction" WHERE transaction_code = %s
                            """, (row['transaction_id'],))
                            result = self.cursor.fetchone()
                            if result:
                                transaction_id = result['transaction_id']
                    
                    # Commit core data (Property, Transaction, etc.)
                    self.conn.commit()
                    
                    # 8. New: Insert appointment records (use separate transaction)
                    try:
                        if buyer_id and pd.notna(row['appointment_history']):
                            self.insert_appointments(
                                row['appointment_history'], 
                                listing_agent_id, 
                                buyer_id, 
                                property_id
                            )
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Appointment insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 9. New: Insert commission record (use separate transaction)
                    try:
                        if transaction_id and pd.notna(row['commission_total']):
                            self.insert_commission_record(
                                transaction_id,
                                row['commission_total'],
                                row['commission_split_info'],
                                row['payout_status'],
                                listing_agent_id,
                                selling_agent_id
                            )
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Commission record insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 10. New: Insert document records (use separate transaction)
                    try:
                        if transaction_id and pd.notna(row['documents_required']):
                            self.insert_documents(
                                row['documents_required'],
                                transaction_id,
                                property_id,
                                self.safe_date(row['inspection_date']),
                                self.safe_decimal(row['appraisal_amount']),
                                listing_agent_id
                            )
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Document record insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 11. New: Insert client lead record (use separate transaction)
                    try:
                        if pd.notna(row['client_buyer_info']) and pd.notna(row['lead_source']):
                            self.insert_client_leads(
                                row['client_buyer_info'],
                                row['lead_source'],
                                property_id,
                                listing_agent_id
                            )
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Client lead insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 12. New: Insert property media records (use separate transaction)
                    try:
                        self.insert_property_media(property_id, listing_agent_id)
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Property media insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 13. Process lease information (enhanced) (use separate transaction)
                    lease_id = None
                    try:
                        if row['transaction_type'] == 'rental' and pd.notna(row['monthly_rent']):
                            lease_start_str = row.get('lease_start_end', '')
                            lease_start, lease_end = None, None
                            
                            if pd.notna(lease_start_str) and ' - ' in str(lease_start_str):
                                try:
                                    start_str, end_str = str(lease_start_str).split(' - ')
                                    lease_start = pd.to_datetime(start_str).date()
                                    lease_end = pd.to_datetime(end_str).date()
                                except:
                                    pass
                            
                            if not lease_start:
                                lease_start = self.safe_date(row['closing_date']) or datetime.now().date()
                                lease_end = lease_start + timedelta(days=365)  # Default one-year lease
                            
                            lease_number = f"LEASE-{row['transaction_id']}"
                            
                            self.cursor.execute("""
                                INSERT INTO Lease (
                                    lease_number, property_id, transaction_id, renter_id, landlord_id,
                                    lease_start_date, lease_end_date, monthly_rent, security_deposit,
                                    lease_terms, created_by
                                ) VALUES (
                                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                                )
                                ON CONFLICT (lease_number) DO NOTHING
                                RETURNING lease_id
                            """, (
                                lease_number,
                                property_id,
                                transaction_id,
                                buyer_id,
                                seller_id,
                                lease_start,
                                lease_end,
                                self.safe_decimal(row['monthly_rent']),
                                self.safe_decimal(row['security_deposit']),
                                row['lease_terms'],
                                listing_agent_id
                            ))
                            
                            result = self.cursor.fetchone()
                            if result:
                                lease_id = result['lease_id']
                            
                            # 14. New: Insert payment records
                            if lease_id:
                                self.insert_payment_records(
                                    lease_id,
                                    row['monthly_rent'],
                                    row['security_deposit']
                                )
                        
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Lease/payment record insertion failed: {e}")
                        self.conn.rollback()
                    
                    # 15. Process marketing campaigns (use separate transaction)
                    try:
                        if pd.notna(row['campaign_type']) and pd.notna(row['marketing_spend']):
                            campaign_name = f"{row['campaign_type']} - {row['mls_listing_number']}"
                            mapped_campaign_type = self.map_campaign_type(row['campaign_type'])
                            
                            self.cursor.execute("""
                                INSERT INTO MarketingCampaign (
                                    property_id, campaign_name, campaign_type, start_date,
                                    budget, actual_cost, status, created_by
                                ) VALUES (
                                    %s, %s, %s, %s, %s, %s, 'completed', %s
                                )
                                ON CONFLICT DO NOTHING
                            """, (
                                property_id,
                                campaign_name,
                                mapped_campaign_type,
                                self.safe_date(row['listing_date']),
                                self.safe_decimal(row['marketing_spend']),
                                self.safe_decimal(row['marketing_spend']),
                                listing_agent_id
                            ))
                        
                        self.conn.commit()
                    except Exception as e:
                        logger.warning(f"Marketing campaign insertion failed: {e}")
                        self.conn.rollback()
                    
                    processed_count += 1
                    
                except Exception as e:
                    logger.error(f"Error processing record {index + 1}: {e}")
                    self.conn.rollback()
                    continue
            
            logger.info(f"Successfully processed {processed_count} records.")
            
        except Exception as e:
            logger.error(f"An error occurred during processing: {e}")
            self.conn.rollback()
            raise
        finally:
            self.close_db()

def main():
    """Main function"""
    from config import DATABASE_CONFIG, CSV_FILE_PATH
    
    etl = EnhancedDreamHomesETL(DATABASE_CONFIG)
    etl.process_data(CSV_FILE_PATH)

if __name__ == "__main__":
    main()
