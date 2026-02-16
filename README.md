# Launchtrack Customer Provisioning

Automated provisioning toolkit for deploying dedicated Launchtrack instances for paying customers. Each customer gets their own Hetzner VPS with Launchtrack (Next.js) + OpenClaw (AI strategic consultant) pre-installed.

## What Gets Deployed

Each customer instance includes:

- **Hetzner CX22 VPS**
  - 4GB RAM, 2 vCPU, 80GB SSD
  - Ubuntu 24.04 LTS
  - Location: Nuremberg (nbg1)
  - Automatic firewall configuration (UFW)

- **Launchtrack Platform**
  - Next.js application on port 3000
  - Connected to customer's Supabase database
  - systemd service for automatic restart
  - nginx reverse proxy for production

- **OpenClaw AI Agent**
  - Gateway on port 18789 (proxied via nginx)
  - Claude Sonnet 4.5 model
  - Dedicated workspace with customer context
  - Strategic consultant persona
  - Proactive heartbeat monitoring
  - systemd service for automatic restart

- **Pre-configured Agent Workspace**
  - SOUL.md — Strategic consultant framework
  - USER.md — Customer profile template
  - IDENTITY.md — Agent identity and mission
  - MEMORY.md — Long-term memory system
  - HEARTBEAT.md — Proactive check-in schedule
  - AGENTS.md — Workspace guidelines
  - TOOLS.md — Customer-specific notes

## Prerequisites

### Local Machine
- Bash shell (Linux, macOS, WSL)
- `curl`, `jq`, `ssh`, `scp` commands
- SSH key pair (default: `~/.ssh/id_rsa`)

### Required Credentials
- **Hetzner Cloud API Token** — Create at https://console.hetzner.cloud/
- **Anthropic API Key** — Get from https://console.anthropic.com/
- **Supabase Project** — Each customer should have their own Supabase project
  - Project URL (e.g., `https://xyz.supabase.co`)
  - Anon/Public Key (from project settings)

### Customer Information
- Customer name (primary contact)
- Company name

## Quick Start

### 1. Clone this repository
```bash
git clone https://github.com/obcraft/launchtrack-install.git
cd launchtrack-install
```

### 2. Make scripts executable
```bash
chmod +x provision.sh setup-server.sh setup-agent.sh
```

### 3. Run provisioning
```bash
./provision.sh \
  --customer-name "Jane Doe" \
  --company-name "TechStart GmbH" \
  --hetzner-token "YOUR_HETZNER_TOKEN" \
  --anthropic-key "sk-ant-YOUR_KEY" \
  --supabase-url "https://xyz.supabase.co" \
  --supabase-key "YOUR_SUPABASE_ANON_KEY"
```

### 4. Wait for deployment (10-15 minutes)
The script will:
- Create Hetzner VPS
- Install all dependencies
- Clone and build Launchtrack
- Install and configure OpenClaw
- Set up systemd services
- Configure nginx reverse proxy
- Initialize agent workspace with customer context

### 5. Configure domain and SSL
```bash
# SSH into the server
ssh root@SERVER_IP

# Set up SSL certificate (replace with customer's domain)
certbot --nginx -d customer-domain.com
```

## What's Deployed

### URLs
- **Launchtrack UI:** `http://SERVER_IP` (or `https://customer-domain.com` after SSL)
- **OpenClaw API:** `http://SERVER_IP/api/openclaw`

### Services
Check service status:
```bash
systemctl status launchtrack
systemctl status openclaw
```

View logs:
```bash
journalctl -u launchtrack -f
journalctl -u openclaw -f
```

Restart services:
```bash
systemctl restart launchtrack
systemctl restart openclaw
```

### File Locations
- **Launchtrack source:** `/opt/launchtrack/`
- **OpenClaw workspace:** `/opt/launchtrack/.openclaw/workspace/`
- **OpenClaw config:** `/opt/launchtrack/.openclaw/openclaw.yaml`
- **Environment variables:** `/opt/launchtrack/.env.local`

## Pricing Context

**Customer subscription:** €1,000/month per dedicated instance

**Infrastructure costs:**
- Hetzner CX22: ~€6/month
- Anthropic API: Variable (usage-based)
- Total overhead: ~€50-150/month depending on usage

**Margin:** ~€850-950/month per customer

## Post-Deployment

### 1. Customer Onboarding
- Schedule onboarding call with customer
- Gather business context (industry, size, challenges, goals)
- Update `/opt/launchtrack/.openclaw/workspace/USER.md` with customer profile
- Begin initial AS-IS analysis

### 2. Domain Configuration
- Customer provides their domain
- Point domain A record to server IP
- Run `certbot --nginx -d customer-domain.com` for SSL

### 3. Messaging Setup
- Customer configures their own messaging channels
- No messaging setup included in provisioning
- Customer connects channels through Launchtrack UI

### 4. Monitoring
- Set up external monitoring (e.g., UptimeRobot)
- Monitor Hetzner Cloud dashboard
- Track API usage in Anthropic console

## Customization

### Change Server Type
```bash
./provision.sh ... --server-type cx32  # 8GB RAM, 4 vCPU
```

### Change Location
```bash
./provision.sh ... --location fsn1  # Falkenstein instead of Nuremberg
```

### Custom SSH Key
```bash
./provision.sh ... --ssh-key-path ~/.ssh/custom_key
```

## Security

- All secrets are passed as command-line arguments (not stored in files)
- SSH key authentication only (no password login)
- UFW firewall enabled (only ports 22, 80, 443)
- nginx reverse proxy for security layer
- systemd services run as root (isolated environment)
- SSL certificate setup required post-deployment

## Troubleshooting

### Provisioning fails
- Check Hetzner API token is valid
- Ensure SSH key exists and is readable
- Verify all required arguments are provided
- Check Hetzner quota (server limits)

### Services won't start
```bash
# Check logs
journalctl -u launchtrack -n 50
journalctl -u openclaw -n 50

# Check configuration
cat /opt/launchtrack/.env.local
cat /opt/launchtrack/.openclaw/openclaw.yaml

# Restart services
systemctl restart launchtrack openclaw
```

### Can't SSH into server
- Wait a few minutes after creation (server may still be booting)
- Check Hetzner Cloud console for server status
- Verify SSH key path is correct
- Try: `ssh -i ~/.ssh/id_rsa root@SERVER_IP`

### Agent not responding
```bash
# Check OpenClaw service
systemctl status openclaw
journalctl -u openclaw -f

# Verify workspace files exist
ls -la /opt/launchtrack/.openclaw/workspace/

# Restart OpenClaw
systemctl restart openclaw
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Customer Instance                     │
│                    (Hetzner CX22 VPS)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐         ┌───────────────────────┐         │
│  │   nginx      │────────▶│  Launchtrack Next.js  │         │
│  │  (port 80)   │         │     (port 3000)       │         │
│  └──────┬───────┘         └───────────────────────┘         │
│         │                                                    │
│         │                  ┌───────────────────────┐         │
│         └─────────────────▶│  OpenClaw Gateway     │         │
│          /api/openclaw     │     (port 18789)      │         │
│                            └──────────┬────────────┘         │
│                                       │                      │
│                            ┌──────────▼────────────┐         │
│                            │  Agent Workspace      │         │
│                            │  - SOUL.md            │         │
│                            │  - USER.md            │         │
│                            │  - MEMORY.md          │         │
│                            │  - HEARTBEAT.md       │         │
│                            └───────────────────────┘         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
                              │         │
                     ┌────────┴─────┐   └──────────────┐
                     ▼              ▼                   ▼
              ┌──────────┐   ┌──────────┐      ┌──────────┐
              │Anthropic │   │ Supabase │      │  Hetzner │
              │   API    │   │   DB     │      │   API    │
              └──────────┘   └──────────┘      └──────────┘
```

## Repository Structure

```
launchtrack-install/
├── provision.sh          # Main orchestrator script
├── setup-server.sh       # Server provisioning (runs on VPS)
├── setup-agent.sh        # Agent workspace configuration (runs on VPS)
├── README.md            # This file
└── templates/           # Agent workspace templates
    ├── SOUL.md.template
    ├── AGENTS.md.template
    ├── USER.md.template
    ├── IDENTITY.md.template
    ├── MEMORY.md.template
    ├── HEARTBEAT.md.template
    └── openclaw.yaml.template
```

## Support

For issues or questions:
- Check [Launchtrack repository](https://github.com/obcraft/Launchtrack)
- Check [OpenClaw documentation](https://github.com/OpenClawHub/openclaw)
- Review server logs: `journalctl -u launchtrack -u openclaw -f`

## License

Proprietary — Launchtrack provisioning system for paying customers only.

---

**Launchtrack: Strategy. Executed.**
