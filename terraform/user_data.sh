#!/bin/bash

set -e

# Update installed packages
dnf update -y

# Install required software
dnf install -y python3 python3-pip git nginx jq

# Create application directory
mkdir -p /opt/python-aws-3tier

# Set application directory ownership
chown ec2-user:ec2-user /opt/python-aws-3tier

# Clone the application from GitHub
git clone --branch main --single-branch \
  https://github.com/nidhiksha-ananth/python-aws-3tier-project.git \
  /opt/python-aws-3tier

# Set ownership
chown -R ec2-user:ec2-user /opt/python-aws-3tier

# Create Python virtual environment
runuser -u ec2-user -- \
  python3 -m venv /opt/python-aws-3tier/venv

# Install Python dependencies and Gunicorn
runuser -u ec2-user -- \
  /opt/python-aws-3tier/venv/bin/pip install --upgrade pip

runuser -u ec2-user -- \
  /opt/python-aws-3tier/venv/bin/pip install \
  -r /opt/python-aws-3tier/requirements.txt gunicorn

  # Install AWS CLI
dnf install -y awscli

# Retrieve RDS credentials from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --region "${aws_region}" \
  --query SecretString \
  --output text > /tmp/db-secret.json

# Create application environment file
DB_NAME="${db_name}" python3 -c '
import json
import os

with open("/tmp/db-secret.json") as f:
    secret = json.load(f)

with open("/opt/python-aws-3tier/.env", "w") as f:
    f.write(f"DB_HOST={secret['\''host'\'']}\n")
    f.write(f"DB_PORT={secret['\''port'\'']}\n")
    f.write("DB_NAME=" + os.environ["DB_NAME"] + "\n")
    f.write(f"DB_USER={secret['\''username'\'']}\n")
    f.write(f"DB_PASSWORD={secret['\''password'\'']}\n")
'

# Protect database credentials
chown ec2-user:ec2-user /opt/python-aws-3tier/.env
chmod 600 /opt/python-aws-3tier/.env

# Remove temporary secret file
rm -f /tmp/db-secret.json

# Create Gunicorn log directory
mkdir -p /var/log/gunicorn
chown ec2-user:ec2-user /var/log/gunicorn

# Create Gunicorn systemd service
cat > /etc/systemd/system/flask-app.service <<'EOF'
[Unit]
Description=Gunicorn Flask Application
After=network.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/python-aws-3tier
ExecStart=/opt/python-aws-3tier/venv/bin/gunicorn \
    --workers 2 \
    --bind 127.0.0.1:5001 \
    --access-logfile /var/log/gunicorn/access.log \
    --error-logfile /var/log/gunicorn/error.log \
    run:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Gunicorn
systemctl daemon-reload
systemctl enable flask-app
systemctl start flask-app

# Configure Nginx reverse proxy
cat > /etc/nginx/conf.d/flask-app.conf <<'EOF'
server {
    listen 5000;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5001;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    }
}
EOF

# Test Nginx configuration
nginx -t

# Enable and start Nginx
systemctl enable nginx
systemctl restart nginx

# Install CloudWatch Agent
dnf install -y amazon-cloudwatch-agent

# Create CloudWatch Agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/${project_name}/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/${project_name}/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/${project_name}/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/gunicorn/access.log",
            "log_group_name": "/${project_name}/application",
            "log_stream_name": "{instance_id}-gunicorn-access"
          },
          {
            "file_path": "/var/log/gunicorn/error.log",
            "log_group_name": "/${project_name}/application",
            "log_stream_name": "{instance_id}-gunicorn-error"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch Agent
systemctl enable amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s