#!/bin/bash

# Update system
apt-get update
apt-get install -y python3 python3-pip python3-venv docker.io

# Start Docker service
systemctl start docker
systemctl enable docker

# Create phoenix user
useradd -m -s /bin/bash phoenix || true
usermod -aG docker phoenix

# Create directory for Phoenix
mkdir -p /opt/phoenix
chown phoenix:phoenix /opt/phoenix

# Create systemd service for Phoenix
cat > /etc/systemd/system/phoenix.service << 'PHOENIX_SERVICE'
[Unit]
Description=Arize Phoenix Server
After=docker.service
Requires=docker.service

[Service]
Type=exec
User=phoenix
Group=phoenix
WorkingDirectory=/opt/phoenix
ExecStartPre=/usr/bin/docker pull arizephoenix/phoenix:PHOENIX_VERSION_PLACEHOLDER
ExecStart=/usr/bin/docker run --rm --name phoenix \
    -p PHOENIX_PORT_PLACEHOLDER:6006 \
    -v /opt/phoenix/data:/phoenix/data \
    -e PHOENIX_SQL_DATABASE_URL=sqlite:////phoenix/data/phoenix.db \
    arizephoenix/phoenix:PHOENIX_VERSION_PLACEHOLDER
ExecStop=/usr/bin/docker stop phoenix
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
PHOENIX_SERVICE

# Replace placeholders in service file
sed -i "s/PHOENIX_VERSION_PLACEHOLDER/PHOENIX_VERSION_PLACEHOLDER/g" /etc/systemd/system/phoenix.service
sed -i "s/PHOENIX_PORT_PLACEHOLDER/PHOENIX_PORT_PLACEHOLDER/g" /etc/systemd/system/phoenix.service

# Create data directory
mkdir -p /opt/phoenix/data
chown -R phoenix:phoenix /opt/phoenix

# Enable and start Phoenix service
systemctl daemon-reload
systemctl enable phoenix
systemctl start phoenix

# Log the startup completion
echo "Phoenix deployment completed at $(date)" >> /opt/phoenix/deployment.log
