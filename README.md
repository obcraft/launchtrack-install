# Launchtrack Customer Provisioning System

Automated provisioning for dedicated Launchtrack instances on Hetzner Cloud VPS.

## Overview

Each paying customer gets their own dedicated Hetzner VPS with:
- **Launchtrack** (Next.js app) on port 3000
- **OpenClaw** (AI strategic consultant) with gateway on port 18789
- **Nginx** reverse proxy for HTTPS (SSL placeholder for later domain setup)
- **Systemd services** for auto-restart and boot persistence
- **Firewall** (UFW) configured for secure access

**Server Specs:** Hetzner CX22 (2 vCPU, 4GB RAM, 40GB SSD, Ubuntu 24.04)

## Prerequisites

Before provisioning:

1. **Hetzner Cloud Account**
   - Create a project at https://console.hetzner.cloud/
   - Generate an API token (Read & Write permissions)

2. **SSH Key**
   - Default: `~/.ssh/id_rsa.pub`
   - Or specify custom path with `--ssh-key-path`

3. **Local Dependencies**
   - `curl` for API calls
   - `ssh` and `scp` for server access
   - `jq` (optional, for JSON parsing)

## Quick Start

```bash
./provision.sh \
  --customer-name "John Doe" \
  --company-name "Acme Corp" \
  --hetzner-token "YOUR_HETZNER_API_TOKEN"
```

This will:
1. Create a Hetzner CX22 VPS (Ubuntu 24.04, Nuremberg datacenter)
2. Wait for server to boot and SSH to be available
3. Install Node.js v24, dependencies, and OpenClaw
4. Configure systemd services for Launchtrack and OpenClaw
5. Set up firewall and nginx reverse proxy
6. Configure the OpenClaw agent with company-specific templates
7. Output server IP, credentials, and next steps

**Provisioning time:** ~10-15 minutes

## Usage

### Basic Usage

```bash
./provision.sh \
  --customer-name "Jane Smith" \
  --company-name "TechStart BV" \
  --hetzner-token "abc123..."
```

### Advanced Options

```bash
./provision.sh \
  --customer-name "Jane Smith" \
  --company-name "TechStart BV" \
  --hetzner-token "abc123..." \
  --ssh-key-path "/path/to/custom/key.pub" \
  --server-name "launchtrack-techstart" \
  --location "nbg1" \
  --server-type "cx22"
```

### Options Reference

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `--customer-name` | Customer contact name | - | Yes |
| `--company-name` | Company name | - | Yes |
| `--hetzner-token` | Hetzner API token | - | Yes |
| `--ssh-key-path` | SSH public key path | `~/.ssh/id_rsa.pub` | No |
| `--server-name` | Server hostname | `launchtrack-<company-slug>` | No |
| `--location` | Hetzner datacenter | `nbg1` (Nuremberg) | No |
| `--server-type` | Server type | `cx22` | No |

**Supported Hetzner Locations:**
- `nbg1` - Nuremberg, Germany (recommended)
- `fsn1` - Falkenstein, Germany
- `hel1` - Helsinki, Finland
- `ash` - Ashburn, USA
- `hil` - Hillsboro, USA

**Available Server Types:**
- `cx22` - 2 vCPU, 4GB RAM (recommended for most)
- `cx32` - 4 vCPU, 8GB RAM (for larger deployments)
- `cx42` - 8 vCPU, 16GB RAM (for enterprise)

## Post-Provisioning Setup

After provisioning completes, follow these steps:

### 1. Configure Environment Variables

SSH into the server:
```bash
ssh root@<SERVER_IP>
```

Edit `/opt/launchtrack/.env.local`:
```bash
nano /opt/launchtrack/.env.local
```

Fill in the required values:
```env
NEXT_PUBLIC_SUPABASE_URL=https://yourproject.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
ANTHROPIC_API_KEY=sk-ant-...
NEXT_PUBLIC_APP_URL=https://yourdomain.com
```

### 2. Configure OpenClaw API Key

Edit `/opt/launchtrack/.openclaw/workspace/openclaw.json`:
```bash
nano /opt/launchtrack/.openclaw/workspace/openclaw.json
```

Update the Anthropic API key:
```json
{
  "anthropic": {
    "api_key": "sk-ant-your-key-here"
  },
  ...
}
```

### 3. Build and Deploy Launchtrack

**Option A: Build on Server (slower)**
```bash
cd /opt/launchtrack
npm install
npm run build
```

**Option B: Build Locally and Sync (recommended)**
```bash
# On your local machine
cd /path/to/Launchtrack
npm install
npm run build

# Sync to server
rsync -avz --exclude node_modules .next/ root@<SERVER_IP>:/opt/launchtrack/.next/
rsync -avz --exclude node_modules public/ root@<SERVER_IP>:/opt/launchtrack/public/
rsync -avz package.json package-lock.json root@<SERVER_IP>:/opt/launchtrack/

# On server, install production dependencies only
ssh root@<SERVER_IP> "cd /opt/launchtrack && npm ci --production"
```

### 4. Start Services

```bash
# Enable services to start on boot
systemctl enable launchtrack
systemctl enable openclaw-gateway

# Start services
systemctl start launchtrack
systemctl start openclaw-gateway

# Check status
systemctl status launchtrack
systemctl status openclaw-gateway
```

### 5. Configure DNS and SSL

1. **Point DNS to server IP**
   - Add an A record: `your-customer.launchtrack.io` → `<SERVER_IP>`
   - Add CNAME for www (optional): `www.your-customer.launchtrack.io` → `your-customer.launchtrack.io`

2. **Install Let's Encrypt SSL**
   ```bash
   apt-get install -y certbot python3-certbot-nginx
   certbot --nginx -d your-customer.launchtrack.io -d www.your-customer.launchtrack.io
   ```

3. **Test auto-renewal**
   ```bash
   certbot renew --dry-run
   ```

### 6. Verify Installation

Test the services:
```bash
# Test Launchtrack
curl http://localhost:3000

# Test OpenClaw Gateway
curl http://localhost:18789/health

# Test from outside
curl http://<SERVER_IP>:3000
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Hetzner VPS (CX22)                 │
│                  Ubuntu 24.04 LTS                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────────────────────────────────────┐  │
│  │            Nginx (Port 80/443)              │  │
│  │           Reverse Proxy + SSL               │  │
│  └────────────┬────────────────────────┬───────┘  │
│               │                        │           │
│  ┌────────────▼────────────┐  ┌────────▼────────┐ │
│  │     Launchtrack         │  │    OpenClaw     │ │
│  │  (Next.js - Port 3000)  │  │ (Gateway 18789) │ │
│  │                         │  │                 │ │
│  │ • Web UI                │  │ • AI Agent      │ │
│  │ • API endpoints         │  │ • Chat API      │ │
│  │ • Supabase client       │  │ • Tool system   │ │
│  └─────────────────────────┘  └─────────────────┘ │
│               │                        │           │
│  ┌────────────▼────────────────────────▼────────┐ │
│  │        Systemd Service Manager              │ │
│  │  • Auto-restart on failure                  │ │
│  │  • Start on boot                            │ │
│  └─────────────────────────────────────────────┘ │
│                                                     │
│  Firewall (UFW): 22, 80, 443, 3000, 18789         │
└─────────────────────────────────────────────────────┘
         │                                │
         ▼                                ▼
   Supabase Cloud                  Anthropic API
   (PostgreSQL)                    (Claude Models)
```

## File Structure

```
launchtrack-install/
├── provision.sh           # Main orchestration script
├── setup-server.sh        # Server setup (runs on VPS)
├── setup-agent.sh         # Agent configuration
├── templates/             # Configuration templates
│   ├── SOUL.md.template           # Strategic consultant persona
│   ├── AGENTS.md.template         # Agent workspace guide
│   ├── USER.md.template           # Client profile template
│   ├── HEARTBEAT.md.template      # Proactive monitoring config
│   └── openclaw-config.yaml.template  # OpenClaw gateway config
└── README.md              # This file
```

## OpenClaw Agent Configuration

Each customer's OpenClaw agent is configured with:

### Core Files

1. **SOUL.md** - The agent's identity as a strategic consultant
   - McKinsey-level strategic thinking
   - Internalized frameworks (Porter's Five Forces, SWOT, OKRs, 7S, etc.)
   - Never names frameworks, delivers insights directly
   - Adapts to company context

2. **AGENTS.md** - Workspace and memory management
   - Session initialization process
   - Memory file structure
   - Safety guidelines

3. **USER.md** - Client profile
   - Company name, industry, size
   - Primary contact and role
   - Business context and goals
   - Communication preferences

4. **HEARTBEAT.md** - Proactive monitoring checklist
   - KPI monitoring (daily)
   - Action item tracking
   - Goal progress reviews
   - Quarterly business reviews
   - Market and industry monitoring
   - Financial health indicators

5. **IDENTITY.md** - Agent instance identity
   - Organization ID
   - Purpose and scope
   - Boundaries

6. **MEMORY.md** - Long-term curated memory
   - Key insights about the business
   - Important decisions made
   - Lessons learned
   - Client preferences

### Workspace Structure

```
/opt/launchtrack/.openclaw/workspace/
├── SOUL.md              # Agent persona
├── AGENTS.md            # Workspace guide
├── USER.md              # Client profile
├── IDENTITY.md          # Instance identity
├── MEMORY.md            # Long-term memory
├── HEARTBEAT.md         # Proactive monitoring
├── openclaw.json        # Gateway config
└── memory/              # Daily logs
    ├── heartbeat-state.json
    └── YYYY-MM-DD.md
```

## Troubleshooting

### Services Not Starting

Check logs:
```bash
journalctl -u launchtrack -n 50
journalctl -u openclaw-gateway -n 50
```

### Port Already in Use

Check what's using the port:
```bash
lsof -i :3000
lsof -i :18789
```

### OpenClaw API Key Issues

Verify the API key is set:
```bash
cat /opt/launchtrack/.openclaw/workspace/openclaw.json | grep api_key
```

Test the key:
```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: YOUR_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'
```

### Firewall Issues

Check firewall status:
```bash
ufw status verbose
```

Temporarily disable for testing (NOT recommended for production):
```bash
ufw disable
```

### Build Issues

If `npm run build` fails due to memory:
- Build locally and rsync (see Option B above)
- Or temporarily upgrade to CX32 (8GB RAM)

## Security Notes

⚠️ **Important Security Considerations:**

1. **Change Default SSH**: Consider changing SSH to non-standard port after setup
2. **API Keys**: Never commit real API keys to git
3. **Firewall**: Keep UFW enabled at all times
4. **Updates**: Regularly update system packages
   ```bash
   apt-get update && apt-get upgrade -y
   ```
5. **Monitoring**: Set up monitoring and alerts (e.g., UptimeRobot, Datadog)
6. **Backups**: Implement regular backups of Supabase data
7. **SSL**: Always use HTTPS in production (Let's Encrypt)

## Maintenance

### Regular Tasks

**Weekly:**
- Check service status: `systemctl status launchtrack openclaw-gateway`
- Review logs: `journalctl -u launchtrack -u openclaw-gateway --since "1 week ago"`
- Check disk usage: `df -h`

**Monthly:**
- Update packages: `apt-get update && apt-get upgrade -y`
- Review OpenClaw memory files
- Check SSL certificate expiry: `certbot certificates`

**Quarterly:**
- Review and update agent configuration
- Optimize memory files (archive old daily logs)
- Review security patches

### Updating Launchtrack

```bash
# On local machine
git pull
npm install
npm run build

# Sync to server
rsync -avz .next/ root@<SERVER_IP>:/opt/launchtrack/.next/

# Restart service
ssh root@<SERVER_IP> "systemctl restart launchtrack"
```

### Updating OpenClaw

```bash
ssh root@<SERVER_IP>
npm update -g openclaw
systemctl restart openclaw-gateway
```

## Cost Estimate

**Monthly Costs per Customer:**

- Hetzner CX22 VPS: €5.83/month (~$6.30)
- Traffic: Included (20TB)
- Backups (optional): €1.17/month (~$1.26)
- Snapshots (as needed): €0.0119/GB/month

**Total: ~€7-8/month per customer** (~$7.50-8.50)

## Support

For issues with:
- **Provisioning scripts**: Check GitHub issues or contact dev team
- **Hetzner**: https://docs.hetzner.com/
- **OpenClaw**: https://docs.openclaw.ai/
- **Next.js**: https://nextjs.org/docs

## License

Internal use only - Launchtrack B.V.

---

**Last Updated:** 2025-02-16
**Version:** 1.0.0
