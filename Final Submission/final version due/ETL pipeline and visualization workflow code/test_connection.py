# 
# This file test_connection.py is built for pre-testing the database connection before running the ETL pipeline
# it is not used in the final version of the ETL pipeline
#
import psycopg2
from psycopg2.extras import RealDictCursor
from config import DATABASE_CONFIG

def test_database_connection():
    try:
        # Test connection
        conn = psycopg2.connect(**DATABASE_CONFIG)
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Test basic query
        cursor.execute("SELECT version();")
        version = cursor.fetchone()
        print(f"✅ Database connection successful!")
        print(f"PostgreSQL version: {version['version']}")
        
        # Test schema
        cursor.execute("""
            SELECT COUNT(*) as table_count 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
        """)
        table_count = cursor.fetchone()['table_count']
        print(f"✅ Found {table_count} tables in database")
        
        # Test ENUM types
        cursor.execute("""
            SELECT COUNT(*) as enum_count 
            FROM pg_type 
            WHERE typtype = 'e'
        """)
        enum_count = cursor.fetchone()['enum_count']
        print(f"✅ Found {enum_count} ENUM types")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        return False

if __name__ == "__main__":
    test_database_connection()