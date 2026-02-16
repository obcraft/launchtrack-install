#!/bin/bash
set -euo pipefail

# OpenClaw Agent Workspace Setup
# Configures the agent workspace with customer-specific context

CUSTOMER_NAME="$1"
COMPANY_NAME="$2"
CURRENT_DATE="$3"

echo "==================================================================="
echo "OpenClaw Agent Workspace Setup"
echo "==================================================================="
echo "Customer:  $CUSTOMER_NAME"
echo "Company:   $COMPANY_NAME"
echo "Date:      $CURRENT_DATE"
echo ""

# Create workspace directory
WORKSPACE_DIR="/opt/launchtrack/.openclaw/workspace"
echo "[1/6] Creating workspace directory..."
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR/memory"

# Process templates
echo "[2/6] Processing templates..."
TEMPLATE_DIR="/root/templates"

# Helper function to process template
process_template() {
    local template_file="$1"
    local output_file="$2"
    
    sed -e "s/{{CUSTOMER_NAME}}/$CUSTOMER_NAME/g" \
        -e "s/{{COMPANY_NAME}}/$COMPANY_NAME/g" \
        -e "s/{{DATE}}/$CURRENT_DATE/g" \
        "$template_file" > "$output_file"
    
    echo "  ✓ Created $(basename $output_file)"
}

# Process all templates
process_template "$TEMPLATE_DIR/SOUL.md.template" "$WORKSPACE_DIR/SOUL.md"
process_template "$TEMPLATE_DIR/AGENTS.md.template" "$WORKSPACE_DIR/AGENTS.md"
process_template "$TEMPLATE_DIR/USER.md.template" "$WORKSPACE_DIR/USER.md"
process_template "$TEMPLATE_DIR/IDENTITY.md.template" "$WORKSPACE_DIR/IDENTITY.md"
process_template "$TEMPLATE_DIR/MEMORY.md.template" "$WORKSPACE_DIR/MEMORY.md"
process_template "$TEMPLATE_DIR/HEARTBEAT.md.template" "$WORKSPACE_DIR/HEARTBEAT.md"
process_template "$TEMPLATE_DIR/openclaw.yaml.template" "/opt/launchtrack/.openclaw/openclaw.yaml"

# Create initial daily memory file
echo "[3/6] Creating initial memory file..."
cat > "$WORKSPACE_DIR/memory/$CURRENT_DATE.md" << EOF
# Daily Memory — $CURRENT_DATE

## Instance Deployed

Launchtrack instance provisioned for **$COMPANY_NAME**.

**Customer:** $CUSTOMER_NAME
**Date:** $CURRENT_DATE
**Status:** Instance deployed and ready for onboarding

## Next Steps

1. Complete onboarding session with $CUSTOMER_NAME
2. Gather business context (industry, size, challenges, goals)
3. Update USER.md with customer profile
4. Begin initial AS-IS analysis

## Notes

- Fresh instance, no prior history
- All systems operational
- Awaiting first customer interaction

EOF

echo "  ✓ Created memory/$CURRENT_DATE.md"

# Create TOOLS.md placeholder
echo "[4/6] Creating TOOLS.md..."
cat > "$WORKSPACE_DIR/TOOLS.md" << EOF
# TOOLS.md - Local Notes

## Customer-Specific Setup

This is a dedicated instance for **$COMPANY_NAME**.

### Environment

- Server location: Hetzner Nuremberg (nbg1)
- Instance type: CX22 (4GB RAM, 2 vCPU)
- OS: Ubuntu 24.04
- Deployed: $CURRENT_DATE

### Services

- Launchtrack: http://localhost:3000
- OpenClaw Gateway: http://localhost:18789

### Customer Preferences

[To be filled in during onboarding]

- Preferred language:
- Communication style:
- Response time expectations:
- Meeting frequency:

### Tools & Integrations

[Document any customer-specific tools or integrations here]

EOF

echo "  ✓ Created TOOLS.md"

# Set proper permissions
echo "[5/6] Setting permissions..."
chown -R root:root "$WORKSPACE_DIR"
chmod -R 755 "$WORKSPACE_DIR"

# Restart OpenClaw to load new configuration
echo "[6/6] Restarting OpenClaw service..."
systemctl restart openclaw
sleep 3

# Verify service is running
if systemctl is-active --quiet openclaw; then
    echo "  ✓ OpenClaw service is running"
else
    echo "  ✗ OpenClaw service failed to start"
    systemctl status openclaw --no-pager
    exit 1
fi

echo ""
echo "==================================================================="
echo "Agent workspace configured successfully!"
echo "==================================================================="
echo ""
echo "Workspace structure:"
echo "  $WORKSPACE_DIR/"
echo "  ├── SOUL.md          (Strategic consultant persona)"
echo "  ├── AGENTS.md        (Agent workspace guide)"
echo "  ├── USER.md          (Customer profile)"
echo "  ├── IDENTITY.md      (Agent identity)"
echo "  ├── MEMORY.md        (Long-term memory)"
echo "  ├── HEARTBEAT.md     (Proactive check-ins)"
echo "  ├── TOOLS.md         (Local notes & preferences)"
echo "  └── memory/"
echo "      └── $CURRENT_DATE.md"
echo ""
echo "OpenClaw configuration:"
echo "  /opt/launchtrack/.openclaw/openclaw.yaml"
echo ""
echo "The agent is now ready to serve $CUSTOMER_NAME!"
echo "==================================================================="
