#!/bin/bash
# =============================================================================
#  Apache2 + PHP7.4 Fix Script for VICIdial on Ubuntu 22.04
#  Run this as root on your server:
#    sudo bash fix_apache.sh
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[FIX]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash fix_apache.sh"

VICI_SHARE="/usr/share/astguiclient"
SERVER_IP=$(hostname -I | awk '{print $1}')

# ── STEP 1: Fix MPM conflict ───────────────────────────────────────────────
info "Step 1: Fixing Apache MPM conflict (mpm_event → mpm_prefork) ..."

# Disable event and worker MPMs
a2dismod mpm_event  2>/dev/null || true
a2dismod mpm_worker 2>/dev/null || true

# Enable prefork (required by mod_php)
a2enmod mpm_prefork

# Make sure prefork config exists and is sane
cat > /etc/apache2/mods-available/mpm_prefork.conf <<'PREFORK'
<IfModule mpm_prefork_module>
    StartServers            5
    MinSpareServers         5
    MaxSpareServers        10
    MaxRequestWorkers     150
    MaxConnectionsPerChild  0
</IfModule>
PREFORK

# ── STEP 2: Disable any conflicting PHP versions ────────────────────────────
info "Step 2: Disabling any other PHP modules ..."
for phpver in 5 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3; do
    a2dismod "php${phpver}" 2>/dev/null || true
done

# ── STEP 3: Enable PHP 7.4 cleanly ─────────────────────────────────────────
info "Step 3: Enabling php7.4 ..."
a2enmod php7.4

# ── STEP 4: Enable other needed modules ────────────────────────────────────
info "Step 4: Enabling rewrite, headers, ssl ..."
a2enmod rewrite headers ssl

# ── STEP 5: Fix the VirtualHost config (shell vars weren't expanded) ────────
info "Step 5: Writing correct VirtualHost config ..."

# Remove broken config
rm -f /etc/apache2/sites-available/vicidial.conf
rm -f /etc/apache2/sites-enabled/vicidial.conf

# Write with literal paths (no shell variable expansion inside single-quoted heredoc)
cat > /etc/apache2/sites-available/vicidial.conf <<APACHECONF
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html
    ServerName ${SERVER_IP}

    DirectoryIndex index.php index.html

    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # VICIdial admin GUI
    Alias /vicidial /usr/share/astguiclient/vicidial
    <Directory /usr/share/astguiclient/vicidial>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # VICIdial agent GUI
    Alias /agc /usr/share/astguiclient/agc
    <Directory /usr/share/astguiclient/agc>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/vicidial_error.log
    CustomLog \${APACHE_LOG_DIR}/vicidial_access.log combined
</VirtualHost>
APACHECONF

# ── STEP 6: Add global ServerName to suppress FQDN warning ─────────────────
info "Step 6: Setting global ServerName ..."
grep -q "^ServerName" /etc/apache2/apache2.conf \
  || echo "ServerName ${SERVER_IP}" >> /etc/apache2/apache2.conf

# ── STEP 7: Enable the site ─────────────────────────────────────────────────
info "Step 7: Enabling vicidial site ..."
a2dissite 000-default.conf 2>/dev/null || true
a2ensite vicidial.conf

# ── STEP 8: Ensure /usr/share/astguiclient dirs exist (Apache will 500 otherwise) ──
info "Step 8: Creating VICIdial web directories if missing ..."
mkdir -p /usr/share/astguiclient/vicidial
mkdir -p /usr/share/astguiclient/agc

# ── STEP 9: Test Apache config before restarting ───────────────────────────
info "Step 9: Testing Apache config ..."
if apache2ctl configtest 2>&1; then
    info "Config OK — restarting Apache ..."
    systemctl restart apache2
    sleep 2
    if systemctl is-active --quiet apache2; then
        info "✔  Apache2 is running!"
        info "   Test: curl -I http://${SERVER_IP}/vicidial/admin.php"
    else
        error "Apache2 still failing. Check: journalctl -xeu apache2.service"
    fi
else
    error "Apache config test FAILED — check errors above."
fi

# ── STEP 10: Verify PHP works ───────────────────────────────────────────────
info "Step 10: Verifying PHP in Apache ..."
echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
info "   PHP info page: http://${SERVER_IP}/phpinfo.php"
info "   (delete after checking: rm /var/www/html/phpinfo.php)"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Apache fix complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "  Apache status : $(systemctl is-active apache2)"
echo -e "  PHP module    : $(apache2ctl -M 2>/dev/null | grep php || echo 'not found')"
echo -e "  Active MPM    : $(apache2ctl -V 2>/dev/null | grep 'MPM Name' || echo 'check above')"
echo ""
