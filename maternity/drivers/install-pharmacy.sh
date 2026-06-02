#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
# M.A.R.T.I.N. — Pharmacy Installer
# Sets up the Dell Driver Cache system:
#   - Installs dependencies
#   - Configures Samba share
#   - Sets up cron job
#   - Optionally runs initial driver sync
# ════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_ROOT="${DRIVER_ROOT:-/var/lib/maternity/drivers}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"  # 2am daily

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

info "Installing M.A.R.T.I.N. Pharmacy..."

# ── Dependencies ───────────────────────────────────────────────────────
info "Installing system dependencies..."
apt-get update -qq && apt-get install -y -qq curl wget cabextract samba smbclient 2>/dev/null
ok "Dependencies installed"

# ── Directories ────────────────────────────────────────────────────────
info "Creating directories..."
mkdir -p "$DRIVER_ROOT" "$DRIVER_ROOT/.cache" /var/log/maternity
ok "Directories created"

# ── Samba Share ────────────────────────────────────────────────────────
info "Configuring Samba share..."
SHARE_CONF="/etc/samba/smb.conf"
if [ -f "$SCRIPT_DIR/driver-share.conf" ]; then
    if grep -q "\[DellDrivers\]" "$SHARE_CONF" 2>/dev/null; then
        ok "Samba share 'DellDrivers' already configured"
    else
        cat "$SCRIPT_DIR/driver-share.conf" >> "$SHARE_CONF"
        # Restart Samba
        systemctl restart smbd 2>/dev/null || service smbd restart 2>/dev/null || true
        ok "Samba share 'DellDrivers' added"
    fi
else
    warn "driver-share.conf not found — configure Samba manually"
fi

# ── Cron Job ───────────────────────────────────────────────────────────
info "Setting up cron job..."
CRON_CMD="$SCRIPT_DIR/driver-cache.sh update >> /var/log/maternity/driver-cache.log 2>&1"
CRON_EXISTING=$(crontab -l 2>/dev/null || echo "")

if echo "$CRON_EXISTING" | grep -q "driver-cache.sh"; then
    ok "Cron job already exists"
else
    (echo "$CRON_EXISTING"; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -
    ok "Cron job added: $CRON_SCHEDULE"
fi

# ── Firewall ───────────────────────────────────────────────────────────
info "Opening Samba ports in firewall..."
for cmd in ufw firewall-cmd iptables; do
    case $cmd in
        ufw)
            if command -v ufw &>/dev/null; then
                ufw allow samba 2>/dev/null || true
            fi
            ;;
        firewall-cmd)
            if command -v firewall-cmd &>/dev/null; then
                firewall-cmd --permanent --add-service=samba 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
            fi
            ;;
    esac
done

# ── Test Share ─────────────────────────────────────────────────────────
info "Testing Samba share..."
if command -v smbclient &>/dev/null; then
    smbclient -L 127.0.0.1 -N 2>&1 | grep -q "DellDrivers" && ok "Samba share reachable" || warn "Samba share not detected (may need restart)"
fi

echo ""
ok "Pharmacy installation complete"
echo ""
info "Next steps:"
info "  1. Populate the driver cache:  sudo driver-cache.sh update"
info "  2. Check status:               sudo driver-cache.sh status"
info "  3. Clients can access:         \\\\$(hostname -I | awk '{print $1}')\\DellDrivers"
info "  4. Cron runs nightly at 2am to refresh drivers"
