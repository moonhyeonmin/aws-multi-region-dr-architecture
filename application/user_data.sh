#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting user data script..."

# Update system
yum update -y

# Install Python 3 and pip
yum install -y python3 python3-pip git

# Install MySQL client (for testing)
yum install -y mysql

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Download application files from a public location or use inline
# For now, we'll create them inline (in production, use S3 or git)
cat > app.py << 'APPPY'
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
    import os
    region = os.getenv('REGION', 'unknown')
    is_replica = os.getenv('IS_REPLICA', 'false')
    print("Initializing database... Region: {}, Is Replica: {}".format(region, is_replica))
    if init_database():
        print("Database initialized successfully")
    else:
        print("Warning: Database initialization failed", file=sys.stderr)
    
    # Run Flask app
    app.run(host='0.0.0.0', port=80, debug=False)
APPPY

# Create templates directory
mkdir -p templates
cat > templates/index.html << 'HTML'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DR Test Application</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #007bff;
            padding-bottom: 10px;
        }
        .info {
            background: #e7f3ff;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .status.primary {
            background: #28a745;
            color: white;
        }
        .status.replica {
            background: #ffc107;
            color: #333;
        }
        .status.connected {
            background: #28a745;
            color: white;
        }
        .status.disconnected {
            background: #dc3545;
            color: white;
        }
        .api-section {
            margin-top: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 5px;
        }
        button {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
        }
        button:hover {
            background: #0056b3;
        }
        pre {
            background: #f4f4f4;
            padding: 10px;
            border-radius: 5px;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS Multi-Region DR Test Application</h1>
        
        <div class="info">
            <h2>시스템 정보</h2>
            <p><strong>리전:</strong> {{ region }}</p>
            <p><strong>역할:</strong> 
                {% if is_replica %}
                <span class="status replica">Read Replica (DR)</span>
                {% else %}
                <span class="status primary">Primary</span>
                {% endif %}
            </p>
            <p><strong>데이터베이스 상태:</strong> 
                <span class="status {{ db_status }}">{{ db_status }}</span>
            </p>
        </div>

        <div class="api-section">
            <h2>API 테스트</h2>
            <p>아래 버튼을 사용하여 API를 테스트할 수 있습니다.</p>
            
            <button onclick="testHealth()">Health Check</button>
            <button onclick="getData()">데이터 조회 (GET)</button>
            <button onclick="createData()">데이터 생성 (POST)</button>
            {% if is_replica %}
            <button onclick="checkReplication()">복제 상태 확인</button>
            {% endif %}

            <div id="result" style="margin-top: 20px;"></div>
        </div>
    </div>

    <script>
        function displayResult(data) {
            const resultDiv = document.getElementById('result');
            resultDiv.innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
        }

        async function testHealth() {
            try {
                const response = await fetch('/health');
                const data = await response.json();
                displayResult(data);
            } catch (error) {
                displayResult({ error: error.message });
            }
        }

        async function getData() {
            try {
                const response = await fetch('/api/data');
                const data = await response.json();
                displayResult(data);
            } catch (error) {
                displayResult({ error: error.message });
            }
        }

        async function createData() {
            const message = prompt('메시지를 입력하세요:');
            if (!message) return;

            try {
                const response = await fetch('/api/data', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ message: message })
                });
                const data = await response.json();
                displayResult(data);
            } catch (error) {
                displayResult({ error: error.message });
            }
        }

        async function checkReplication() {
            try {
                const response = await fetch('/api/replication-status');
                const data = await response.json();
                displayResult(data);
            } catch (error) {
                displayResult({ error: error.message });
            }
        }
    </script>
</body>
</html>
HTML

# Create requirements.txt
cat > requirements.txt << 'REQ'
Flask==3.0.0
PyMySQL==1.1.0
REQ

# Install Python dependencies
pip3 install -r requirements.txt

# Set environment variables
cat > /etc/environment << EOF
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
REGION=${region}
IS_REPLICA=${is_replica}
EOF

# Create systemd service
cat > /etc/systemd/system/flask-app.service << 'EOF'
[Unit]
Description=Flask DR Test Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
EnvironmentFile=/etc/environment
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start the service
systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app

echo "User data script completed"

