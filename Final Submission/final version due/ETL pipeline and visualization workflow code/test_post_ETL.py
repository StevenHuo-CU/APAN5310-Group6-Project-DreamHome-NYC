# 
# This file test_post_ETL.py is built for validating the ETL pipeline and visualization workflow,
# specifically, it is used for test the file etl_enhanced.py
# it is not used in the final version of the ETL pipeline
#

import psycopg2
from psycopg2.extras import RealDictCursor
from config import DATABASE_CONFIG

def validate_etl_results():
    conn = psycopg2.connect(**DATABASE_CONFIG)
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    print("🔍 ETL Results Validation & Business Intelligence Report")
    print("=" * 80)
    
    # ========== BASIC DATA VALIDATION ==========
    print("\n📊 BASIC DATA VALIDATION")
    print("-" * 50)
    
    # Check record counts by table
    tables_to_check = [
        'Office', 'Employee', 'Client', 'ClientRole', 'PropertyType',
        'Property', 'PropertyFeature', '"Transaction"', 'Commission',
        'Appointment', 'Document', 'ClientLead', 'PropertyMedia',
        'Lease', 'PaymentRecord', 'MarketingCampaign'
    ]
    
    total_records = 0
    for table in tables_to_check:
        cursor.execute(f"SELECT COUNT(*) as count FROM {table}")
        count = cursor.fetchone()['count']
        total_records += count
        status = "✅" if count > 0 else "⚠️"
        print(f"{status} {table:<20}: {count:>5} records")
    
    print("-" * 50)
    print(f"📊 Total records inserted: {total_records}")
    
    # Check data integrity
    cursor.execute("""
        SELECT 
            COUNT(*) as properties,
            COUNT(CASE WHEN current_status = 'sold' THEN 1 END) as sold,
            COUNT(CASE WHEN current_status = 'rented' THEN 1 END) as rented,
            COUNT(CASE WHEN current_status = 'active' THEN 1 END) as active
        FROM Property
    """)
    
    property_stats = cursor.fetchone()
    print(f"\n🏠 Property Status Distribution:")
    print(f"   Total Properties: {property_stats['properties']}")
    print(f"   Sold: {property_stats['sold']}")
    print(f"   Rented: {property_stats['rented']}")
    print(f"   Active: {property_stats['active']}")
    
    # Check transaction types
    cursor.execute("""
        SELECT 
            transaction_type,
            COUNT(*) as count,
            COALESCE(AVG(transaction_amount), 0) as avg_amount
        FROM "Transaction"
        WHERE transaction_amount IS NOT NULL
        GROUP BY transaction_type
    """)
    
    print(f"\n💰 Transaction Summary:")
    for row in cursor.fetchall():
        if row['avg_amount']:
            print(f"   {row['transaction_type'].title()}: {row['count']} transactions, Avg: ${row['avg_amount']:,.2f}")
        else:
            print(f"   {row['transaction_type'].title()}: {row['count']} transactions")
    
    # ========== BUSINESS INTELLIGENCE QUERIES ==========
    print("\n" + "=" * 80)
    print("📈 BUSINESS INTELLIGENCE INSIGHTS")
    print("=" * 80)
    
    # ========== QUERY 1: Property Management Company Performance ==========
    print("\n🏢 QUERY #6: Which property management companies perform the best?")
    print("-" * 60)
    
    try:
        cursor.execute("""
            SELECT o.office_name, o.city as office_location,
                   COUNT(DISTINCT e.employee_id) as total_staff,
                   COUNT(DISTINCT p.property_id) as properties_managed,
                   COUNT(DISTINCT c.client_id) as clients_served,
                   COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as successful_transactions,
                   ROUND(COUNT(CASE WHEN t.status = 'completed' THEN 1 END) * 100.0 / NULLIF(COUNT(t.transaction_id), 0), 2) as transaction_success_rate
            FROM Office o
            JOIN Employee e ON o.office_id = e.office_id
            LEFT JOIN Property p ON e.employee_id = p.listing_agent_id
            LEFT JOIN Client c ON e.employee_id = c.assigned_agent_id
            LEFT JOIN "Transaction" t ON p.property_id = t.property_id
            GROUP BY o.office_id, o.office_name, o.city
            HAVING COUNT(DISTINCT p.property_id) >= 1
            ORDER BY transaction_success_rate DESC, properties_managed DESC
            LIMIT 5
        """)
        
        office_results = cursor.fetchall()
        if office_results:
            for office in office_results:
                print(f"   🏢 {office['office_name']} ({office['office_location']})")
                print(f"      Staff: {office['total_staff']}, Properties: {office['properties_managed']}")
                print(f"      Success Rate: {office['transaction_success_rate']}%")
                print()
        else:
            print("   ⚠️ No office performance data available")
            
    except Exception as e:
        print(f"   ❌ Query failed: {e}")
    
    # ========== QUERY 2: Best Rental Agents ==========
    print("\n🏆 QUERY #4: Who are the best rental agents in the area?")
    print("-" * 60)
    
    try:
        cursor.execute("""
            SELECT e.first_name || ' ' || e.last_name as agent_name,
                   e.phone, e.email,
                   o.office_name,
                   COUNT(DISTINCT p.property_id) as rental_properties_managed,
                   COUNT(DISTINCT l.lease_id) as active_leases,
                   ROUND(AVG(l.monthly_rent), 0) as avg_rental_price
            FROM Employee e
            JOIN Office o ON e.office_id = o.office_id
            JOIN Property p ON e.employee_id = p.listing_agent_id
            JOIN Lease l ON p.property_id = l.property_id
            WHERE p.current_status = 'rented'
            GROUP BY e.employee_id, e.first_name, e.last_name, e.phone, e.email, o.office_name
            HAVING COUNT(DISTINCT l.lease_id) >= 1
            ORDER BY rental_properties_managed DESC
            LIMIT 5
        """)
        
        agent_results = cursor.fetchall()
        if agent_results:
            for agent in agent_results:
                print(f"   🏆 {agent['agent_name']} - {agent['office_name']}")
                print(f"      Properties: {agent['rental_properties_managed']}, Leases: {agent['active_leases']}")
                print(f"      Avg Rent: ${agent['avg_rental_price']:,}, Contact: {agent['phone']}")
                print()
        else:
            print("   ⚠️ No rental agent data available")
            
    except Exception as e:
        print(f"   ❌ Query failed: {e}")
    
    # ========== QUERY 3: Property Value Analysis by Size ==========
    print("\n📐 QUERY #10: What house size gives the best value for money?")
    print("-" * 60)
    
    try:
        cursor.execute("""
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
                   ROUND(AVG(sc.list_price / sc.square_footage), 2) as avg_price_per_sqft
            FROM size_categories sc
            JOIN Property p ON sc.property_id = p.property_id
            GROUP BY sc.size_category
            ORDER BY avg_price_per_sqft ASC
        """)
        
        size_results = cursor.fetchall()
        if size_results:
            for size in size_results:
                print(f"   📐 {size['size_category']}")
                print(f"      Count: {size['property_count']}, Avg Price: ${size['avg_list_price']:,}")
                print(f"      Price per sqft: ${size['avg_price_per_sqft']}")
                print()
        else:
            print("   ⚠️ No property size data available")
            
    except Exception as e:
        print(f"   ❌ Query failed: {e}")
    
    # ========== QUERY 4: Marketing Campaign Performance ==========
    print("\n📢 QUERY #2: Which marketing strategies work best and what do they cost?")
    print("-" * 60)
    
    try:
        cursor.execute("""
            SELECT mc.campaign_type,
                   COUNT(*) as total_campaigns,
                   ROUND(AVG(mc.budget), 0) as avg_budget,
                   ROUND(AVG(mc.actual_cost), 0) as avg_actual_cost,
                   COUNT(CASE WHEN p.current_status = 'sold' THEN 1 END) as properties_sold,
                   ROUND(COUNT(CASE WHEN p.current_status = 'sold' THEN 1 END) * 100.0 / COUNT(*), 2) as success_rate
            FROM MarketingCampaign mc
            JOIN Property p ON mc.property_id = p.property_id
            WHERE mc.status = 'active' OR mc.status = 'completed'
            GROUP BY mc.campaign_type
            HAVING COUNT(*) >= 1
            ORDER BY success_rate DESC
        """)
        
        marketing_results = cursor.fetchall()
        if marketing_results:
            for campaign in marketing_results:
                print(f"   📢 {campaign['campaign_type'].title()} Marketing")
                print(f"      Campaigns: {campaign['total_campaigns']}, Success Rate: {campaign['success_rate']}%")
                print(f"      Avg Budget: ${campaign['avg_budget']:,}, Avg Cost: ${campaign['avg_actual_cost']:,}")
                print()
        else:
            print("   ⚠️ No marketing campaign data available")
            
    except Exception as e:
        print(f"   ❌ Query failed: {e}")
    
    # ========== QUERY 5: Property Features Analysis ==========
    print("\n🏠 QUERY #1: What features and amenities are most common?")
    print("-" * 60)
    
    try:
        cursor.execute("""
            SELECT pf.feature_type,
                   pf.feature_name,
                   COUNT(*) as feature_count,
                   ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Property WHERE current_status IN ('active', 'sold')), 2) as percentage_of_properties
            FROM PropertyFeature pf
            JOIN Property p ON pf.property_id = p.property_id
            WHERE p.current_status IN ('active', 'sold')
            GROUP BY pf.feature_type, pf.feature_name
            HAVING COUNT(*) >= 2
            ORDER BY feature_count DESC
            LIMIT 10
        """)
        
        feature_results = cursor.fetchall()
        if feature_results:
            for feature in feature_results:
                print(f"   🏠 {feature['feature_name']} ({feature['feature_type']})")
                print(f"      Found in: {feature['feature_count']} properties ({feature['percentage_of_properties']}%)")
                print()
        else:
            print("   ⚠️ No property feature data available")
            
    except Exception as e:
        print(f"   ❌ Query failed: {e}")
    
    # ========== SUMMARY INSIGHTS ==========
    print("\n" + "=" * 80)
    print("🎯 KEY INSIGHTS SUMMARY")
    print("=" * 80)
    
    # Get key metrics for summary
    try:
        cursor.execute("""
            SELECT 
                COUNT(DISTINCT p.property_id) as total_properties,
                COUNT(DISTINCT e.employee_id) as total_agents,
                COUNT(DISTINCT o.office_id) as total_offices,
                COUNT(DISTINCT c.client_id) as total_clients,
                COUNT(CASE WHEN t.status = 'completed' THEN 1 END) as completed_transactions,
                ROUND(AVG(CASE WHEN p.current_status = 'sold' THEN t.transaction_amount END), 0) as avg_sale_price,
                ROUND(AVG(CASE WHEN p.current_status = 'rented' THEN l.monthly_rent END), 0) as avg_rent_price
            FROM Property p
            LEFT JOIN Employee e ON p.listing_agent_id = e.employee_id
            LEFT JOIN Office o ON e.office_id = o.office_id
            LEFT JOIN Client c ON e.employee_id = c.assigned_agent_id
            LEFT JOIN "Transaction" t ON p.property_id = t.property_id
            LEFT JOIN Lease l ON p.property_id = l.property_id
        """)
        
        summary = cursor.fetchone()
        if summary:
            print(f"📊 Portfolio Overview:")
            print(f"   • {summary['total_properties']} properties across {summary['total_offices']} offices")
            print(f"   • {summary['total_agents']} active agents serving {summary['total_clients']} clients")
            print(f"   • {summary['completed_transactions']} completed transactions")
            print(f"   • Average sale price: ${summary['avg_sale_price']:,}" if summary['avg_sale_price'] else "   • No sale price data")
            print(f"   • Average rental price: ${summary['avg_rent_price']:,}/month" if summary['avg_rent_price'] else "   • No rental price data")
        
    except Exception as e:
        print(f"❌ Summary calculation failed: {e}")
    
    print("\n✅ ETL Validation and Business Intelligence Report Complete!")
    print("🎯 Data is ready for Metabase dashboard visualization!")
    print("=" * 80)
    
    cursor.close()
    conn.close()

if __name__ == "__main__":
    validate_etl_results()