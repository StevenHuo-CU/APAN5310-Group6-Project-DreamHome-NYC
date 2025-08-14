# config.py
import os

# Database Configuration
DATABASE_CONFIG = {
    'host': 'localhost',              # Your PostgreSQL host
    'database': 'dream_homes_db',     # Database name
    'user': 'postgres',             # Database user
    'password': '123',   # Database password
    'port': 5432                      # PostgreSQL port
}

# CSV File Path - adjust path as needed
CSV_FILE_PATH = 'dream_homes_nyc_dataset_v8.csv'

# Optional: Environment variable overrides for security
DATABASE_CONFIG['host'] = os.getenv('DB_HOST', DATABASE_CONFIG['host'])
DATABASE_CONFIG['database'] = os.getenv('DB_NAME', DATABASE_CONFIG['database']) 
DATABASE_CONFIG['user'] = os.getenv('DB_USER', DATABASE_CONFIG['user'])
DATABASE_CONFIG['password'] = os.getenv('DB_PASSWORD', DATABASE_CONFIG['password'])
DATABASE_CONFIG['port'] = int(os.getenv('DB_PORT', DATABASE_CONFIG['port']))