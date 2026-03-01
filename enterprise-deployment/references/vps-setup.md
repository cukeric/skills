# VPS Setup & Server Hardening Reference

## Initial Server Provisioning

Run these steps immediately after creating a new VPS. This guide assumes Ubuntu 24.04 LTS.

### Step 1: Connect & Update

```bash
# Connect as root (first time only)
ssh root@YOUR_SERVER_IP

# Update system
apt update && apt upgrade -y
apt install -y curl wget git unzip htop ncdu ufw fail2ban

# Set timezone
timenod set-timezone UTC

# Set hostname
hostnamectl set-hostname myapp-prod-01
```

### Step 2: Create Deploy User (Never Use Root)

```bash
# Create user with home directory
adduser deploy --disabled-password --gecos ""

# Add to sudo group
usermod -aG sudo deploy

# Allow sudo without password (for automated deploys)
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy

# Copy SSH authorized keys from root to deploy user
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

### Step 3: SSH Hardening

```bash
# Edit SSH config
cat > /etc/ssh/sshd_config.d/hardened.conf << 'EOF'
# Disable root login
PermitRootLogin no

# Disable password authentication (key only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Limit SSH to deploy user
AllowUsers deploy

# Connection limits
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Idle timeout (5 minutes)
ClientAliveInterval 300
ClientAliveCountMax 0

# Disable X11 and agent forwarding
X11Forwarding no
AllowAgentForwarding no

# Use strong key exchange and ciphers
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

# Restart SSH (keep your current session open!)
systemctl restart sshd

# TEST: Open a NEW terminal and verify you can connect as deploy
# ssh deploy@YOUR_SERVER_IP
# Only close the root session after confirming deploy user works
```

### Step 4: Firewall (UFW)

```bash
# Default deny incoming, allow outgoing
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (do this BEFORE enabling!)
ufw allow 22/tcp comment 'SSH'

# Allow HTTP and HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Enable firewall
ufw enable

# Verify
ufw status verbose
```

**Only these three ports should be open: 22, 80, 443.** If you need additional ports (e.g., for a database from a specific IP), add them explicitly:

```bash
# Allow PostgreSQL from specific IP only
ufw allow from 10.0.0.5 to any port 5432 comment 'DB from app server'
```

### Step 5: Fail2ban (Brute-Force Protection)

```bash
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600       # 1 hour ban
findtime = 600       # 10 minute window
maxretry = 5         # 5 attempts
banaction = ufw

[sshd]
enabled = true
port = 22
filter = sshd
maxretry = 3         # Stricter for SSH
bantime = 86400      # 24 hour ban for SSH brute force
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Check status
fail2ban-client status sshd
```

### Step 6: Automatic Security Updates

```bash
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Configure to auto-reboot if needed (at 3 AM)
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

systemctl enable unattended-upgrades
```

### Step 7: Swap Space (for small VPS)

```bash
# Add 2GB swap (if VPS has ≤ 4GB RAM)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Optimize swap behavior
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p
```

### Step 8: Install Docker

```bash
# Docker official install
curl -fsSL https://get.docker.com | sh

# Add deploy user to docker group
usermod -aG docker deploy

# Enable Docker on boot
systemctl enable docker

# Install Docker Compose plugin
apt install -y docker-compose-plugin

# Verify
docker --version
docker compose version
```

---

## Directory Structure on Server

```
/home/deploy/
├── apps/
│   └── myapp/                 # Application directory
│       ├── docker-compose.yml
│       ├── .env               # Production environment variables
│       └── data/              # Persistent volumes
│           ├── postgres/
│           └── redis/
├── backups/                   # Local backup staging
├── scripts/
│   ├── deploy.sh
│   └── backup.sh
└── .ssh/
    └── authorized_keys
```

---

## Deploy Script

```bash
#!/bin/bash
# /home/deploy/scripts/deploy.sh
set -euo pipefail

APP_DIR="/home/deploy/apps/myapp"
REGISTRY="ghcr.io/your-org"
IMAGE="myapp-api"
TAG="${1:-latest}"

echo "🚀 Deploying $IMAGE:$TAG..."

cd "$APP_DIR"

# Pull new image
docker compose pull

# Run database migrations
docker compose run --rm api npx prisma migrate deploy

# Rolling restart (zero-downtime with health check)
docker compose up -d --remove-orphans

# Wait for health check
echo "⏳ Waiting for health check..."
for i in $(seq 1 30); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "✅ Deployment successful — app is healthy"
    docker image prune -f  # Clean up old images
    exit 0
  fi
  echo "  Attempt $i: status $STATUS"
  sleep 5
done

echo "❌ Health check failed — rolling back"
docker compose rollback 2>/dev/null || docker compose up -d --force-recreate
exit 1
```

---

## Security Audit Commands

Run periodically to verify hardening:

```bash
# Check open ports
ss -tlnp

# Check active SSH sessions
who

# Check fail2ban bans
fail2ban-client status sshd

# Check firewall rules
ufw status numbered

# Check for rootkits (install: apt install rkhunter)
rkhunter --check

# Check disk usage
df -h
ncdu /

# Check running containers
docker ps
docker stats --no-stream

# Check system logs for auth failures
journalctl -u sshd --since "1 hour ago" | grep -i "failed\|invalid"
```

---

## Checklist

- [ ] Root login disabled, deploy user with SSH key only
- [ ] UFW firewall: only ports 22, 80, 443 open
- [ ] Fail2ban active on SSH (3 attempts, 24hr ban)
- [ ] Automatic security updates enabled
- [ ] Docker installed, deploy user in docker group
- [ ] Swap configured (if ≤ 4GB RAM)
- [ ] Timezone set to UTC
- [ ] Hostname set to meaningful name
- [ ] SSH uses strong ciphers and key exchange algorithms
