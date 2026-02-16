#!/bin/bash
set -euo pipefail

# Launchtrack Customer Provisioning Script
# Creates a new Hetzner VPS with Launchtrack + OpenClaw pre-installed

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
HETZNER_LOCATION="nbg1"
HETZNER_SERVER_TYPE="cx22"
HETZNER_IMAGE="ubuntu-24.04"
SSH_KEY_NAME="launchtrack-provisioning"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 --customer-name NAME --company-name COMPANY --hetzner-token TOKEN \\
          --anthropic-key KEY --supabase-url URL --supabase-key KEY

Required arguments:
  --customer-name NAME     Primary contact name (e.g., "John Smith")
  --company-name COMPANY   Company name (e.g., "Acme Corp")
  --hetzner-token TOKEN    Hetzner Cloud API token
  --anthropic-key KEY      Anthropic API key for Claude
  --supabase-url URL       Supabase project URL
  --supabase-key KEY       Supabase anon/public key

Optional arguments:
  --server-type TYPE       Hetzner server type (default: cx22)
  --location LOC           Hetzner datacenter (default: nbg1)
  --ssh-key-path PATH      Path to SSH private key (default: ~/.ssh/id_rsa)

Example:
  $0 --customer-name "Jane Doe" --company-name "TechStart GmbH" \\
     --hetzner-token abc123... --anthropic-key sk-ant-... \\
     --supabase-url https://xyz.supabase.co --supabase-key eyJh...

EOF
    exit 1
}

# Parse arguments
CUSTOMER_NAME=""
COMPANY_NAME=""
HETZNER_TOKEN=""
ANTHROPIC_KEY=""
SUPABASE_URL=""
SUPABASE_KEY=""
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

while [[ $# -gt 0 ]]; do
    case $1 in
        --customer-name)
            CUSTOMER_NAME="$2"
            shift 2
            ;;
        --company-name)
            COMPANY_NAME="$2"
            shift 2
            ;;
        --hetzner-token)
            HETZNER_TOKEN="$2"
            shift 2
            ;;
        --anthropic-key)
            ANTHROPIC_KEY="$2"
            shift 2
            ;;
        --supabase-url)
            SUPABASE_URL="$2"
            shift 2
            ;;
        --supabase-key)
            SUPABASE_KEY="$2"
            shift 2
            ;;
        --server-type)
            HETZNER_SERVER_TYPE="$2"
            shift 2
            ;;
        --location)
            HETZNER_LOCATION="$2"
            shift 2
            ;;
        --ssh-key-path)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$CUSTOMER_NAME" ]] || [[ -z "$COMPANY_NAME" ]] || [[ -z "$HETZNER_TOKEN" ]] || \
   [[ -z "$ANTHROPIC_KEY" ]] || [[ -z "$SUPABASE_URL" ]] || [[ -z "$SUPABASE_KEY" ]]; then
    log_error "Missing required arguments"
    usage
fi

# Validate SSH key exists
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    log_error "SSH private key not found at $SSH_KEY_PATH"
    exit 1
fi

SSH_PUBLIC_KEY_PATH="${SSH_KEY_PATH}.pub"
if [[ ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
    log_error "SSH public key not found at $SSH_PUBLIC_KEY_PATH"
    exit 1
fi

# Generate server name
SERVER_NAME=$(echo "$COMPANY_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
SERVER_NAME="launchtrack-${SERVER_NAME}"
CURRENT_DATE=$(date +%Y-%m-%d)

log_info "==================================================================="
log_info "Launchtrack Customer Provisioning"
log_info "==================================================================="
log_info "Customer:      $CUSTOMER_NAME"
log_info "Company:       $COMPANY_NAME"
log_info "Server name:   $SERVER_NAME"
log_info "Server type:   $HETZNER_SERVER_TYPE"
log_info "Location:      $HETZNER_LOCATION"
log_info "Date:          $CURRENT_DATE"
log_info "==================================================================="
echo ""

# Check for required commands
for cmd in curl jq ssh scp; do
    if ! command -v $cmd &> /dev/null; then
        log_error "Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Step 1: Upload SSH key to Hetzner (if not already there)
log_info "Checking SSH key in Hetzner..."
SSH_PUBLIC_KEY=$(cat "$SSH_PUBLIC_KEY_PATH")
SSH_KEY_ID=$(curl -s -H "Authorization: Bearer $HETZNER_TOKEN" \
    https://api.hetzner.cloud/v1/ssh_keys | \
    jq -r ".ssh_keys[] | select(.name == \"$SSH_KEY_NAME\") | .id")

if [[ -z "$SSH_KEY_ID" ]] || [[ "$SSH_KEY_ID" == "null" ]]; then
    log_info "Uploading SSH key to Hetzner..."
    SSH_KEY_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $HETZNER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$SSH_KEY_NAME\", \"public_key\": \"$SSH_PUBLIC_KEY\"}" \
        https://api.hetzner.cloud/v1/ssh_keys)
    SSH_KEY_ID=$(echo "$SSH_KEY_RESPONSE" | jq -r '.ssh_key.id')
    log_success "SSH key uploaded (ID: $SSH_KEY_ID)"
else
    log_success "SSH key already exists (ID: $SSH_KEY_ID)"
fi

# Step 2: Create Hetzner server
log_info "Creating Hetzner server..."
CREATE_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $HETZNER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$SERVER_NAME\",
        \"server_type\": \"$HETZNER_SERVER_TYPE\",
        \"location\": \"$HETZNER_LOCATION\",
        \"image\": \"$HETZNER_IMAGE\",
        \"ssh_keys\": [$SSH_KEY_ID],
        \"labels\": {
            \"service\": \"launchtrack\",
            \"company\": \"$(echo $COMPANY_NAME | tr ' ' '_')\",
            \"customer\": \"$(echo $CUSTOMER_NAME | tr ' ' '_')\"
        }
    }" \
    https://api.hetzner.cloud/v1/servers)

SERVER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.server.id')
if [[ -z "$SERVER_ID" ]] || [[ "$SERVER_ID" == "null" ]]; then
    log_error "Failed to create server"
    echo "$CREATE_RESPONSE" | jq .
    exit 1
fi

SERVER_IP=$(echo "$CREATE_RESPONSE" | jq -r '.server.public_net.ipv4.ip')
log_success "Server created (ID: $SERVER_ID, IP: $SERVER_IP)"

# Step 3: Wait for server to be ready
log_info "Waiting for server to start..."
for i in {1..60}; do
    SERVER_STATUS=$(curl -s -H "Authorization: Bearer $HETZNER_TOKEN" \
        https://api.hetzner.cloud/v1/servers/$SERVER_ID | jq -r '.server.status')
    
    if [[ "$SERVER_STATUS" == "running" ]]; then
        log_success "Server is running"
        break
    fi
    
    echo -n "."
    sleep 5
done
echo ""

# Step 4: Wait for SSH to be available
log_info "Waiting for SSH to be available..."
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i $SSH_KEY_PATH"
for i in {1..60}; do
    if ssh $SSH_OPTS root@$SERVER_IP "echo 'SSH ready'" &> /dev/null; then
        log_success "SSH is available"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Step 5: Copy setup scripts to server
log_info "Copying setup scripts to server..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp $SSH_OPTS "$SCRIPT_DIR/setup-server.sh" root@$SERVER_IP:/root/
scp $SSH_OPTS "$SCRIPT_DIR/setup-agent.sh" root@$SERVER_IP:/root/
scp -r $SSH_OPTS "$SCRIPT_DIR/templates" root@$SERVER_IP:/root/
log_success "Scripts copied"

# Step 6: Run server setup
log_info "Running server setup (this may take 10-15 minutes)..."
ssh $SSH_OPTS root@$SERVER_IP "bash /root/setup-server.sh \
    '$ANTHROPIC_KEY' \
    '$SUPABASE_URL' \
    '$SUPABASE_KEY'"
log_success "Server setup completed"

# Step 7: Run agent setup
log_info "Configuring OpenClaw agent workspace..."
ssh $SSH_OPTS root@$SERVER_IP "bash /root/setup-agent.sh \
    '$CUSTOMER_NAME' \
    '$COMPANY_NAME' \
    '$CURRENT_DATE'"
log_success "Agent workspace configured"

# Step 8: Output summary
echo ""
log_info "==================================================================="
log_success "Launchtrack Instance Deployed Successfully!"
log_info "==================================================================="
echo ""
echo "Company:         $COMPANY_NAME"
echo "Customer:        $CUSTOMER_NAME"
echo "Server IP:       $SERVER_IP"
echo "Server ID:       $SERVER_ID"
echo "Server Name:     $SERVER_NAME"
echo ""
echo "Access URLs:"
echo "  - Launchtrack:    http://$SERVER_IP"
echo "  - OpenClaw API:   http://$SERVER_IP/api/openclaw"
echo ""
echo "Next Steps:"
echo "  1. Point customer's domain to $SERVER_IP"
echo "  2. SSH into server: ssh -i $SSH_KEY_PATH root@$SERVER_IP"
echo "  3. Set up SSL with: certbot --nginx -d customer-domain.com"
echo "  4. Configure messaging channels (customer does this themselves)"
echo "  5. Complete onboarding session with $CUSTOMER_NAME"
echo ""
echo "Service Status:"
echo "  - Launchtrack:    systemctl status launchtrack"
echo "  - OpenClaw:       systemctl status openclaw"
echo ""
echo "Logs Location:"
echo "  - Launchtrack:    journalctl -u launchtrack -f"
echo "  - OpenClaw:       journalctl -u openclaw -f"
echo ""
log_info "==================================================================="
echo ""
