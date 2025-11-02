#!/usr/bin/env python3
"""
Simple Flask web application for DR testing
"""
import os
import sys
import json
from flask import Flask, render_template, request, jsonify
import pymysql
from datetime import datetime

app = Flask(__name__)

# Configuration from environment variables
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER', 'admin'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'testdb'),
    'charset': 'utf8mb4',
    'connect_timeout': 10
}

REGION = os.getenv('REGION', 'unknown')
IS_REPLICA = os.getenv('IS_REPLICA', 'false').lower() == 'true'


def get_db_connection():
    """Get database connection"""
    try:
        connection = pymysql.connect(**DB_CONFIG)
        return connection
    except Exception as e:
        print(f"Database connection error: {e}", file=sys.stderr)
        return None


def init_database():
    """Initialize database tables"""
    connection = get_db_connection()
    if not connection:
        return False
    
    try:
        with connection.cursor() as cursor:
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS test_data (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    message VARCHAR(255) NOT NULL,
                    region VARCHAR(50) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_created_at (created_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
            connection.commit()
            return True
    except Exception as e:
        print(f"Database initialization error: {e}", file=sys.stderr)
        return False
    finally:
        connection.close()


@app.route('/')
def index():
    """Main page showing region information"""
    connection = get_db_connection()
    db_status = "connected" if connection else "disconnected"
    if connection:
        connection.close()
    
    return render_template('index.html', 
                         region=REGION,
                         is_replica=IS_REPLICA,
                         db_status=db_status)


@app.route('/health')
def health():
    """Health check endpoint"""
    connection = get_db_connection()
    if not connection:
        return jsonify({
            'status': 'unhealthy',
            'region': REGION,
            'timestamp': datetime.utcnow().isoformat(),
            'error': 'Database connection failed'
        }), 503
    
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        
        connection.close()
        return jsonify({
            'status': 'healthy',
            'region': REGION,
            'is_replica': IS_REPLICA,
            'timestamp': datetime.utcnow().isoformat()
        }), 200
    except Exception as e:
        connection.close()
        return jsonify({
            'status': 'unhealthy',
            'region': REGION,
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 503


@app.route('/api/data', methods=['GET'])
def get_data():
    """Get all data from database"""
    # Read Replica는 읽기는 가능 (쓰기만 막음)
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute("""
                SELECT id, message, region, created_at 
                FROM test_data 
                ORDER BY created_at DESC 
                LIMIT 100
            """)
            results = cursor.fetchall()
            # Convert datetime to string for JSON serialization
            for result in results:
                if result['created_at']:
                    result['created_at'] = result['created_at'].isoformat()
        
        connection.close()
        return jsonify({
            'count': len(results),
            'data': results,
            'region': REGION
        }), 200
    except Exception as e:
        connection.close()
        return jsonify({'error': str(e)}), 500


@app.route('/api/data', methods=['POST'])
def create_data():
    """Create new data entry"""
    if IS_REPLICA:
        return jsonify({
            'error': 'Read replica - write operations not allowed'
        }), 403
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        data = request.get_json()
        if not data or 'message' not in data:
            return jsonify({'error': 'message field is required'}), 400
        
        message = data['message'][:255]  # Limit message length
        
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO test_data (message, region) 
                VALUES (%s, %s)
            """, (message, REGION))
            connection.commit()
            insert_id = cursor.lastrowid
        
        connection.close()
        return jsonify({
            'id': insert_id,
            'message': message,
            'region': REGION,
            'status': 'created'
        }), 201
    except Exception as e:
        connection.close()
        return jsonify({'error': str(e)}), 500


@app.route('/api/replication-status', methods=['GET'])
def replication_status():
    """Check replication status (for replica only)"""
    if not IS_REPLICA:
        return jsonify({
            'error': 'This endpoint is only available on replica instances'
        }), 404
    
    connection = get_db_connection()
    if not connection:
        return jsonify({'error': 'Database connection failed'}), 500
    
    try:
        with connection.cursor(pymysql.cursors.DictCursor) as cursor:
            # Get replication status
            cursor.execute("SHOW SLAVE STATUS")
            slave_status = cursor.fetchone()
            
            if slave_status:
                return jsonify({
                    'is_replica': True,
                    'slave_io_running': slave_status.get('Slave_IO_Running'),
                    'slave_sql_running': slave_status.get('Slave_SQL_Running'),
                    'seconds_behind_master': slave_status.get('Seconds_Behind_Master'),
                    'master_host': slave_status.get('Master_Host'),
                    'region': REGION
                }), 200
            else:
                return jsonify({
                    'is_replica': True,
                    'status': 'No replication status found',
                    'region': REGION
                }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        connection.close()


if __name__ == '__main__':
    # Initialize database
    print(f"Initializing database... Region: {REGION}, Is Replica: {IS_REPLICA}")
    if init_database():
        print("Database initialized successfully")
    else:
        print("Warning: Database initialization failed", file=sys.stderr)
    
    # Run Flask app
    app.run(host='0.0.0.0', port=80, debug=False)

