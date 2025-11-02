#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting user data script..."

# Update system
yum update -y

# Install Python 3, pip, git, and wget
yum install -y python3 python3-pip git wget

# Install MySQL client (for testing)
yum install -y mysql

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Download application from GitHub (or use a simple inline version)
# For simplicity, we'll create a minimal app that downloads the full version
GITHUB_REPO="https://raw.githubusercontent.com/moonhyeonmin/aws-multi-region-dr-architecture/main/application"

# Download app.py, requirements.txt, and template
wget -q "$GITHUB_REPO/app.py" -O app.py || {
    echo "Warning: Could not download app.py, using minimal version"
    # Create minimal fallback
    cat > app.py << 'MINIAPP'
#!/usr/bin/env python3
import os
from flask import Flask, jsonify
import pymysql
app = Flask(__name__)

DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER', 'admin'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'testdb'),
}

@app.route('/')
def index():
    return jsonify({'region': os.getenv('REGION', 'unknown'), 'status': 'ok'})

@app.route('/health')
def health():
    try:
        conn = pymysql.connect(**DB_CONFIG)
        conn.close()
        return jsonify({'status': 'healthy', 'region': os.getenv('REGION', 'unknown')}), 200
    except:
        return jsonify({'status': 'unhealthy'}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
MINIAPP
}

wget -q "$GITHUB_REPO/requirements.txt" -O requirements.txt || {
    echo "Flask==3.0.0" > requirements.txt
    echo "PyMySQL==1.1.0" >> requirements.txt
}

mkdir -p templates
wget -q "$GITHUB_REPO/templates/index.html" -O templates/index.html || {
    echo "<html><body><h1>DR Test App</h1><p>Region: {{ region }}</p></body></html>" > templates/index.html
}

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
