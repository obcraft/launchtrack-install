#!/bin/bash
set -euo pipefail

# Launchtrack Server Setup Script
# Runs on the VPS to install and configure all required software

ANTHROPIC_KEY="$1"
SUPABASE_URL="$2"
SUPABASE_KEY="$3"

echo "==================================================================="
echo "Launchtrack Server Setup"
echo "==================================================================="
echo "Starting server provisioning..."
echo ""

# Update system
echo "[1/12] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl wget git build-essential nginx certbot python3-certbot-nginx ufw

# Install Node.js v24
echo "[2/12] Installing Node.js v24..."
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y -qq nodejs

# Verify Node installation
NODE_VERSION=$(node --version)
echo "Node.js installed: $NODE_VERSION"

# Configure UFW firewall
echo "[3/12] Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "Firewall configured (ports 22, 80, 443)"

# Clone Launchtrack repository
echo "[4/12] Cloning Launchtrack repository..."
if [ -d "/opt/launchtrack" ]; then
    rm -rf /opt/launchtrack
fi
mkdir -p /opt
cd /opt
git clone https://github.com/obcraft/Launchtrack.git launchtrack
cd launchtrack

# Install dependencies
echo "[5/12] Installing Launchtrack dependencies..."
npm install --quiet

# Create .env.local
echo "[6/12] Creating environment configuration..."
cat > /opt/launchtrack/.env.local << EOF
# Anthropic API
ANTHROPIC_API_KEY=$ANTHROPIC_KEY

# Supabase
NEXT_PUBLIC_SUPABASE_URL=$SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY=$SUPABASE_KEY

# OpenClaw
OPENCLAW_GATEWAY_URL=http://localhost:18789

# Production settings
NODE_ENV=production
EOF

# Build Next.js application
echo "[7/12] Building Launchtrack application..."
npm run build

# Install OpenClaw globally
echo "[8/12] Installing OpenClaw..."
npm install -g openclaw --ignore-scripts --quiet

# Create systemd service for Launchtrack
echo "[9/12] Creating Launchtrack systemd service..."
cat > /etc/systemd/system/launchtrack.service << 'EOF'
[Unit]
Description=Launchtrack Next.js Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/launchtrack
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start -- -p 3000
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for OpenClaw
echo "[10/12] Creating OpenClaw systemd service..."
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/launchtrack
Environment=ANTHROPIC_API_KEY=%ANTHROPIC_KEY%
Environment=SUPABASE_URL=%SUPABASE_URL%
Environment=SUPABASE_KEY=%SUPABASE_KEY%
ExecStart=/usr/bin/openclaw gateway start --allow-unconfigured
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Replace placeholders in openclaw.service
sed -i "s|%ANTHROPIC_KEY%|$ANTHROPIC_KEY|g" /etc/systemd/system/openclaw.service
sed -i "s|%SUPABASE_URL%|$SUPABASE_URL|g" /etc/systemd/system/openclaw.service
sed -i "s|%SUPABASE_KEY%|$SUPABASE_KEY|g" /etc/systemd/system/openclaw.service

# Configure nginx
echo "[11/12] Configuring nginx reverse proxy..."
cat > /etc/nginx/sites-available/launchtrack << 'EOF'
server {
    listen 80;
    server_name _;

    client_max_body_size 50M;

    # Launchtrack Next.js application
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # OpenClaw API
    location /api/openclaw {
        proxy_pass http://localhost:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/launchtrack /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# Enable and start services
echo "[12/12] Starting services..."
systemctl daemon-reload
systemctl enable launchtrack openclaw nginx
systemctl start launchtrack
sleep 5
systemctl start openclaw

echo ""
echo "==================================================================="
echo "Server setup completed successfully!"
echo "==================================================================="
echo "Services status:"
systemctl status launchtrack --no-pager | grep Active || true
systemctl status openclaw --no-pager | grep Active || true
systemctl status nginx --no-pager | grep Active || true
echo ""
echo "Next step: Run setup-agent.sh to configure the OpenClaw workspace"
echo "==================================================================="
