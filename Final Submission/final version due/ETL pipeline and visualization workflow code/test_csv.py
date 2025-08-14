# 
# This file test_csv.py is built for pre-testing the csv file before running the ETL pipeline
# it is not used in the final version of the ETL pipeline
#
import pandas as pd
from config import CSV_FILE_PATH

def verify_csv_data():
    try:
        # Read CSV
        df = pd.read_csv(CSV_FILE_PATH)
        print(f"✅ CSV file loaded successfully")
        print(f"📊 Records found: {len(df)}")
        print(f"📊 Columns found: {len(df.columns)}")
        
        # Show first few column names
        print(f"📋 Key columns: {list(df.columns[:10])}")
        
        # Check for required columns (from ETL code analysis)
        required_columns = [
            'transaction_id', 'mls_listing_number', 'property_type',
            'listing_agent_name', 'client_buyer_info', 'transaction_type',
            'list_price', 'status_current'
        ]
        
        missing_columns = [col for col in required_columns if col not in df.columns]
        if missing_columns:
            print(f"⚠️ Missing columns: {missing_columns}")
        else:
            print(f"✅ All required columns present")
            
        return True
        
    except Exception as e:
        print(f"❌ CSV verification failed: {e}")
        return False

if __name__ == "__main__":
    verify_csv_data()