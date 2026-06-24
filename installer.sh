#!/bin/bash
# =============================================================================
#  VICIdial Full Installation Script for Ubuntu 20.04 / 22.04
#  Asterisk 18.21.0-vici  |  VICIdial 2.14 (SVN trunk / "version 9" series)
#
#  USAGE:
#    chmod +x vicidial_install.sh
#    sudo bash vicidial_install.sh
#
#  WHAT THIS SCRIPT DOES (in order):
#    1.  Cleans junk / old installs from /usr/src
#    2.  Updates OS and installs all build dependencies
#    3.  Installs MariaDB and sets up VICIdial databases/users
#    4.  Installs Apache2 + PHP 7.4 (ondrej PPA)
#    5.  Installs required Perl modules
#    6.  Downloads and compiles Asterisk 18.21.0-vici
#    7.  Installs Asterisk sounds (GSM + ULAW)
#    8.  Installs asterisk-perl
#    9.  Checks out VICIdial from SVN (trunk = 2.14 series)
#   10.  Runs VICIdial installer and DB import
#   11.  Configures Apache vhost for /vicidial
#   12.  Writes /etc/astguiclient.conf
#   13.  Sets up all required cron jobs
#   14.  Enables and starts all services
#   15.  Configures basic UFW firewall rules
#
#  DEFAULT CREDENTIALS (change before going to production!):
#    MySQL root password : ViciR00t!
#    MySQL cron user     : cron / 1234
#    MySQL custom user   : custom / custom1234
#    VICIdial admin GUI  : http://<SERVER_IP>/vicidial/admin.php
#                          user: 6666  pass: 1234
# =============================================================================

set -euo pipefail

### ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

### ── Must run as root ────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root (sudo bash vicidial_install.sh)"

### ── Detect Ubuntu version ───────────────────────────────────────────────────
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
info "Detected Ubuntu $UBUNTU_VER"
[[ "$UBUNTU_VER" == "20.04" || "$UBUNTU_VER" == "22.04" ]] \
  || warn "Script tested on 20.04/22.04; continuing anyway on $UBUNTU_VER"

### ── Config variables (edit here) ───────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
MYSQL_ROOT_PASS="ViciR00t!"
MYSQL_CRON_PASS="1234"
MYSQL_CUSTOM_PASS="custom1234"
AST_VERSION="18.21.0"
AST_TARBALL="asterisk-${AST_VERSION}-vici.tar.gz"
VICI_DOWNLOAD_BASE="https://download.vicidial.com/required-apps"
SVN_REPO="svn://svn.eflo.net/agc_2-X/trunk"
VICI_SRC="/usr/src/astguiclient"
AST_SRC="/usr/src"

info "Server IP detected as: $SERVER_IP"
info "Asterisk version     : $AST_VERSION"
info "VICIdial SVN trunk   : $SVN_REPO"

# =============================================================================
# STEP 1 – CLEAN JUNK FROM /usr/src
# =============================================================================
info "=== STEP 1: Cleaning old build artifacts from /usr/src ==="

OLD_PATTERNS=(
  "asterisk*"
  "zaptel*"
  "dahdi*"
  "libpri*"
  "astguiclient*"
  "vicidial*"
  "eaccelerator*"
)

for pattern in "${OLD_PATTERNS[@]}"; do
  find "$AST_SRC" -maxdepth 1 -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
done
info "Old build directories removed."

# =============================================================================
# STEP 2 – OS UPDATE + BUILD DEPENDENCIES
# =============================================================================
info "=== STEP 2: Updating OS and installing dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

# Core build tools
apt-get install -y \
  build-essential \
  gcc \
  g++ \
  make \
  automake \
  autoconf \
  libtool \
  pkg-config \
  cmake

# Version control
apt-get install -y subversion git

# Linux headers (needed for DAHDI)
apt-get install -y linux-headers-$(uname -r) linux-source || \
  apt-get install -y linux-headers-generic || true

# Asterisk build dependencies
apt-get install -y \
  libssl-dev \
  libncurses5-dev \
  libnewt-dev \
  libxml2-dev \
  libsqlite3-dev \
  libjansson-dev \
  uuid-dev \
  libedit-dev \
  libsrtp2-dev \
  libogg-dev \
  libvorbis-dev \
  libcurl4-openssl-dev \
  libiksemel-dev \
  libgmime-3.0-dev \
  unixodbc-dev \
  liblua5.2-dev \
  libopus-dev \
  libspeex-dev \
  libspeexdsp-dev \
  libgnutls28-dev \
  liburiparser-dev \
  libresample1-dev

# Apache, MariaDB, PHP
apt-get install -y \
  apache2 \
  mariadb-server \
  mariadb-client

# PHP 7.4 via ondrej PPA (required for VICIdial compatibility)
apt-get install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt-get update -y
apt-get install -y \
  php7.4 \
  php7.4-mysql \
  php7.4-mbstring \
  php7.4-xml \
  php7.4-curl \
  php7.4-gd \
  php7.4-bcmath \
  php7.4-intl \
  libapache2-mod-php7.4

# Set PHP 7.4 as default
update-alternatives --set php /usr/bin/php7.4 || true

# Audio/media tools
apt-get install -y \
  sox \
  lame \
  ffmpeg \
  mpg123 \
  flac \
  libsox-fmt-all

# Perl and CPAN modules
apt-get install -y \
  perl \
  libdbi-perl \
  libdbd-mysql-perl \
  libterm-readline-gnu-perl \
  libwww-perl \
  liblwp-protocol-https-perl \
  libcrypt-ssleay-perl \
  libnet-ssleay-perl \
  libio-socket-ssl-perl \
  libdigest-md5-perl \
  libtime-hires-perl \
  libnet-telnet-perl \
  libhtml-parser-perl \
  libfile-slurp-perl \
  libmime-base64-perl

# Network/utility
apt-get install -y \
  screen \
  wget \
  curl \
  unzip \
  zip \
  bzip2 \
  ngrep \
  tcpdump \
  net-tools \
  dnsutils \
  ufw \
  fail2ban \
  rsync \
  ntpdate \
  bc \
  sysstat

# ntp sync
ntpdate -u pool.ntp.org 2>/dev/null || timedatectl set-ntp true || true

info "All OS packages installed."

# =============================================================================
# STEP 3 – MARIADB SETUP
# =============================================================================
info "=== STEP 3: Configuring MariaDB ==="

systemctl enable mariadb
systemctl start mariadb

# Secure the installation silently
mysql -u root <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL

# Create VICIdial databases and users
mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL
SET GLOBAL connect_timeout=60;

CREATE DATABASE IF NOT EXISTS \`asterisk\`
  DEFAULT CHARACTER SET utf8
  COLLATE utf8_unicode_ci;

-- cron user
CREATE USER IF NOT EXISTS 'cron'@'localhost' IDENTIFIED BY '${MYSQL_CRON_PASS}';
CREATE USER IF NOT EXISTS 'cron'@'%'         IDENTIFIED BY '${MYSQL_CRON_PASS}';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'localhost';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'%';
GRANT RELOAD ON *.* TO 'cron'@'localhost';
GRANT RELOAD ON *.* TO 'cron'@'%';

-- custom user
CREATE USER IF NOT EXISTS 'custom'@'localhost' IDENTIFIED BY '${MYSQL_CUSTOM_PASS}';
CREATE USER IF NOT EXISTS 'custom'@'%'         IDENTIFIED BY '${MYSQL_CUSTOM_PASS}';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'localhost';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'%';
GRANT RELOAD ON *.* TO 'custom'@'localhost';
GRANT RELOAD ON *.* TO 'custom'@'%';

FLUSH PRIVILEGES;
EOSQL

# MariaDB performance tuning
cat >> /etc/mysql/mariadb.conf.d/99-vicidial.cnf <<'MYCNF'
[mysqld]
innodb_buffer_pool_size        = 512M
innodb_log_file_size           = 128M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method            = O_DIRECT
max_connections                = 300
thread_cache_size              = 100
query_cache_type               = 1
query_cache_size               = 64M
key_buffer_size                = 32M
max_allowed_packet             = 64M
wait_timeout                   = 600
interactive_timeout            = 600
MYCNF

systemctl restart mariadb
info "MariaDB configured."

# =============================================================================
# STEP 4 – APACHE + PHP CONFIGURATION
# =============================================================================
info "=== STEP 4: Configuring Apache + PHP ==="

# PHP tweaks
PHP_INI="/etc/php/7.4/apache2/php.ini"
sed -i 's/^max_execution_time.*/max_execution_time = 600/'       "$PHP_INI"
sed -i 's/^memory_limit.*/memory_limit = 512M/'                  "$PHP_INI"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/'     "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 64M/'                 "$PHP_INI"
sed -i 's/^;date.timezone.*/date.timezone = America\/Chicago/'   "$PHP_INI"

# Enable Apache modules
a2enmod rewrite headers php7.4

# Apache VHost for VICIdial
cat > /etc/apache2/sites-available/vicidial.conf <<APACHECONF
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html
    ServerName ${SERVER_IP}

    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    Alias /vicidial /usr/share/astguiclient/vicidial
    <Directory /usr/share/astguiclient/vicidial>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/vicidial_error.log
    CustomLog \${APACHE_LOG_DIR}/vicidial_access.log combined
</VirtualHost>
APACHECONF

a2ensite vicidial.conf
a2dissite 000-default.conf 2>/dev/null || true
systemctl enable apache2
systemctl restart apache2
info "Apache + PHP configured."

# =============================================================================
# STEP 5 – ADDITIONAL PERL MODULES VIA CPAN
# =============================================================================
info "=== STEP 5: Installing Perl CPAN modules ==="

# Install without interactive prompt
PERL_MM_USE_DEFAULT=1 cpan -T \
  DBI \
  DBD::mysql \
  Net::Telnet \
  Crypt::MD5 \
  Digest::MD5 \
  Time::HiRes \
  IO::Socket \
  LWP::UserAgent \
  HTTP::Request \
  URI::Escape \
  2>/dev/null || warn "Some CPAN modules may have warnings; continuing."

info "Perl modules installed."

# =============================================================================
# STEP 6 – DOWNLOAD AND COMPILE ASTERISK 18.21.0-vici
# =============================================================================
info "=== STEP 6: Compiling Asterisk ${AST_VERSION}-vici ==="

cd "$AST_SRC"

info "Downloading Asterisk ${AST_TARBALL} ..."
wget -q --show-progress \
  "${VICI_DOWNLOAD_BASE}/${AST_TARBALL}" \
  -O "${AST_TARBALL}"

tar -xzf "${AST_TARBALL}"
cd "asterisk-${AST_VERSION}-vici"

info "Running install_prereq ..."
./contrib/scripts/install_prereq install

info "Running bootstrap ..."
./bootstrap.sh

info "Configuring Asterisk (this takes a moment) ..."
./configure \
  --libdir=/usr/lib \
  --with-gsm=internal \
  --enable-opus \
  --enable-srtp \
  --with-ssl \
  --with-pjproject-bundled \
  2>&1 | tail -5

info "Running make menuselect (non-interactive) ..."
make menuselect.makeopts
menuselect/menuselect \
  --enable chan_sip \
  --enable res_srtp \
  --enable codec_opus \
  --enable format_mp3 \
  --enable app_meetme \
  --enable app_queue \
  --enable cdr_mysql \
  --disable BUILD_NATIVE \
  menuselect.makeopts

info "Building Asterisk (this takes 5-15 minutes) ..."
make -j"$(nproc)" 2>&1 | tail -20

info "Installing Asterisk ..."
make install
make config
make samples

# Create asterisk user
id asterisk &>/dev/null || useradd -r -d /var/lib/asterisk -s /sbin/nologin asterisk

# Set ownership
chown -R asterisk:asterisk /etc/asterisk
chown -R asterisk:asterisk /var/lib/asterisk
chown -R asterisk:asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/spool/asterisk
chown -R asterisk:asterisk /usr/lib/asterisk

# Set runuser in /etc/default/asterisk
sed -i 's/^#AST_USER.*/AST_USER="asterisk"/'   /etc/default/asterisk 2>/dev/null || true
sed -i 's/^#AST_GROUP.*/AST_GROUP="asterisk"/' /etc/default/asterisk 2>/dev/null || true

info "Asterisk ${AST_VERSION} installed."

# =============================================================================
# STEP 7 – ASTERISK SOUNDS
# =============================================================================
info "=== STEP 7: Installing Asterisk sounds ==="

SOUNDS_DIR="/var/lib/asterisk/sounds"
mkdir -p "$SOUNDS_DIR"
cd "$AST_SRC"

for SOUND_TGZ in \
  asterisk-core-sounds-en-gsm-current.tar.gz \
  asterisk-core-sounds-en-ulaw-current.tar.gz \
  asterisk-extra-sounds-en-gsm-current.tar.gz \
  asterisk-extra-sounds-en-ulaw-current.tar.gz \
  asterisk-moh-freeplay-gsm.tar.gz \
  asterisk-moh-freeplay-ulaw.tar.gz
do
  info "  Downloading $SOUND_TGZ ..."
  wget -q --show-progress "${VICI_DOWNLOAD_BASE}/${SOUND_TGZ}" -O "$SOUND_TGZ"
  tar -xzf "$SOUND_TGZ" -C "$SOUNDS_DIR" || warn "Could not extract $SOUND_TGZ"
done

chown -R asterisk:asterisk "$SOUNDS_DIR"
info "Sounds installed."

# =============================================================================
# STEP 8 – ASTERISK-PERL
# =============================================================================
info "=== STEP 8: Installing asterisk-perl ==="

cd "$AST_SRC"
wget -q --show-progress "${VICI_DOWNLOAD_BASE}/asterisk-perl-0.08.tar.gz" -O asterisk-perl-0.08.tar.gz
tar -xzf asterisk-perl-0.08.tar.gz
cd asterisk-perl-0.08
perl Makefile.PL
make
make install
info "asterisk-perl installed."

# =============================================================================
# STEP 9 – CHECKOUT VICIDIAL SVN (TRUNK = 2.14 / version 9 series)
# =============================================================================
info "=== STEP 9: Checking out VICIdial SVN trunk ==="

mkdir -p "$VICI_SRC"
cd "$VICI_SRC"
svn checkout "$SVN_REPO" trunk
cd trunk

info "VICIdial source checked out."

# =============================================================================
# STEP 10 – VICIDIAL DATABASE IMPORT + INSTALL
# =============================================================================
info "=== STEP 10: Importing VICIdial database schema ==="

# The standard VICIdial DB SQL file
SQL_FILE=$(find "$VICI_SRC/trunk" -maxdepth 3 -name "*.sql" | grep -i 'VDCL\|vicidial\|asterisk' | head -1)

if [[ -n "$SQL_FILE" ]]; then
  info "  Importing $SQL_FILE ..."
  mysql -u root -p"${MYSQL_ROOT_PASS}" asterisk < "$SQL_FILE"
else
  warn "  No SQL dump found; will rely on VICIdial installer."
fi

# Run VICIdial installer if present
INSTALL_SCRIPT=$(find "$VICI_SRC/trunk" -maxdepth 2 -name "VICIDIAL_install.pl" | head -1)
if [[ -n "$INSTALL_SCRIPT" ]]; then
  info "  Running $INSTALL_SCRIPT ..."
  perl "$INSTALL_SCRIPT" \
    --dbpass="${MYSQL_ROOT_PASS}" \
    --cronpass="${MYSQL_CRON_PASS}" \
    2>&1 || warn "Installer returned non-zero; check manually."
else
  warn "  VICIDIAL_install.pl not found; copying files manually."
fi

# Copy web files
info "  Copying web files to /usr/share/astguiclient ..."
mkdir -p /usr/share/astguiclient
cp -r "$VICI_SRC/trunk/"* /usr/share/astguiclient/ 2>/dev/null || true

# AGI scripts
AGI_BIN="/var/lib/asterisk/agi-bin"
mkdir -p "$AGI_BIN"
find /usr/share/astguiclient -maxdepth 2 -name "*.agi" -exec cp {} "$AGI_BIN/" \; 2>/dev/null || true
find /usr/share/astguiclient -maxdepth 2 -name "*.pl"  -exec cp {} "$AGI_BIN/" \; 2>/dev/null || true
chmod 755 "$AGI_BIN/"*
chown -R asterisk:asterisk "$AGI_BIN"

# Make all VICIdial Perl scripts executable
find /usr/share/astguiclient -name "*.pl" -exec chmod +x {} \;

info "VICIdial files deployed."

# =============================================================================
# STEP 11 – /etc/astguiclient.conf
# =============================================================================
info "=== STEP 11: Writing /etc/astguiclient.conf ==="

cat > /etc/astguiclient.conf <<AGICCONF
# VICIdial AGI client configuration
# Auto-generated by vicidial_install.sh

PATHhome=/usr/share/astguiclient
PATHlogs=/var/log/astguiclient
PATHagi=/var/lib/asterisk/agi-bin
PATHweb=/usr/share/astguiclient/vicidial
PATHsounds=/var/lib/asterisk/sounds
PATHmonitor=/var/spool/asterisk/monitor
PATHDONEmonitor=/var/spool/asterisk/monitorDONE

VARserver_ip=${SERVER_IP}
VARDB_server=localhost
VARDB_database=asterisk
VARDB_user=cron
VARDB_pass=${MYSQL_CRON_PASS}
VARDB_port=3306
VARDB_custom_user=custom
VARDB_custom_pass=${MYSQL_CUSTOM_PASS}

VARFTP_host=localhost
VARFTP_user=ftp
VARFTP_pass=ftp
VARFTP_dir=/
VARHTTP_path=http://${SERVER_IP}

VARASTERISKrestartcommand=/usr/sbin/asterisk -rx "core restart gracefully"
VARASTERISKpath=/usr/sbin
VARASTERISK_outbound_CID=
AGCCONF

chmod 640 /etc/astguiclient.conf
info "/etc/astguiclient.conf written."

# =============================================================================
# STEP 12 – ASTERISK CONFIGURATION (sip.conf, extensions.conf, etc.)
# =============================================================================
info "=== STEP 12: Configuring Asterisk ==="

AST_CONF="/etc/asterisk"

# --- sip.conf ---
cat > "$AST_CONF/sip.conf" <<'SIPCONF'
[general]
context=default
allowoverlap=no
bindport=5060
bindaddr=0.0.0.0
srvlookup=yes
language=en
disallow=all
allow=ulaw
allow=gsm
nat=force_rport,comedia
qualify=yes
qualifyfreq=60
t1min=100
rtptimeout=60
rtpholdtimeout=300
session-timers=refuse
trustrpid=yes
sendrpid=yes
; Adjust for your SIP trunk below
;[YOUR_TRUNK]
;type=peer
;host=sip.yourprovider.com
;username=YOUR_USER
;secret=YOUR_PASS
;fromuser=YOUR_USER
;fromdomain=sip.yourprovider.com
;insecure=port,invite
;dtmfmode=rfc2833
;disallow=all
;allow=ulaw
SIPCONF

# --- extensions.conf: include VICIdial contexts ---
cat > "$AST_CONF/extensions.conf" <<'EXTCONF'
[general]
static=yes
writeprotect=no

[globals]
AGENTEXTEN=8300
VMAIL_SERVER=localhost

#include "extensions_vici.conf"
EXTCONF

# Copy VICIdial-supplied Asterisk conf files if present
VICI_AST=$(find /usr/share/astguiclient -maxdepth 3 -name "extensions_vici.conf" | head -1)
if [[ -n "$VICI_AST" ]]; then
  cp "$VICI_AST" "$AST_CONF/extensions_vici.conf"
  info "  Copied extensions_vici.conf"
else
  touch "$AST_CONF/extensions_vici.conf"
  warn "  extensions_vici.conf not found; created empty placeholder."
fi

# --- manager.conf (AMI) ---
cat > "$AST_CONF/manager.conf" <<'AMICONF'
[general]
enabled=yes
port=5038
bindaddr=127.0.0.1

[cron]
secret=1234
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.0
read=system,call,log,verbose,command,agent,originate
write=system,call,log,verbose,command,agent,originate

[custom]
secret=custom1234
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.0
read=system,call,log,verbose,command,agent,originate
write=system,call,log,verbose,command,agent,originate
AMICONF

# --- musiconhold.conf ---
cat > "$AST_CONF/musiconhold.conf" <<'MOHCONF'
[default]
mode=files
directory=/var/lib/asterisk/sounds/moh
MOHCONF

# --- modules.conf: ensure chan_sip and app_meetme load ---
cat > "$AST_CONF/modules.conf" <<'MODCONF'
[modules]
autoload=yes
noload=chan_pjsip.so
load=chan_sip.so
load=app_meetme.so
load=app_queue.so
load=res_musiconhold.so
MODCONF

# Create required directories
mkdir -p /var/log/astguiclient
mkdir -p /var/spool/asterisk/monitor
mkdir -p /var/spool/asterisk/monitorDONE
mkdir -p /var/lib/asterisk/sounds/moh

chown -R asterisk:asterisk /var/log/astguiclient
chown -R asterisk:asterisk /var/spool/asterisk
chown -R asterisk:asterisk /var/lib/asterisk

info "Asterisk configured."

# =============================================================================
# STEP 13 – CRON JOBS
# =============================================================================
info "=== STEP 13: Installing VICIdial cron jobs ==="

CRON_FILE="/var/spool/cron/crontabs/root"
mkdir -p /var/spool/cron/crontabs

cat >> "$CRON_FILE" <<'CRONEOF'
MAILTO=""
# VICIdial Hopper updater (every minute)
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q
# Adjust GMT offset for leads (twice daily)
1 1,7 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug --postal-code-gmt
# Optimize database tables
3 1 * * * /usr/share/astguiclient/AST_DB_optimize.pl
# Agent weekly summary
2 0 * * 0 /usr/share/astguiclient/AST_agent_week.pl
# Agent daily summary
22 0 * * * /usr/share/astguiclient/AST_agent_day.pl
# Agent log cleanup
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl
50 0 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours
# Audio move and mix (every 3 minutes)
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
# Audio compression (GSM)
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --GSM
# Remove old recordings (>7 days)
24 0 * * * /usr/bin/find /var/spool/asterisk/monitor -maxdepth 2 -type f -mtime +7 -print | xargs rm -f
24 0 * * * /usr/bin/find /var/spool/asterisk/monitorDONE -maxdepth 2 -type f -mtime +7 -print | xargs rm -f
# Remove old VICIdial/Asterisk logs (>2 days)
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
28 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
CRONEOF

chmod 600 "$CRON_FILE"
chown root:crontab "$CRON_FILE" 2>/dev/null || true
info "Cron jobs installed."

# =============================================================================
# STEP 14 – START SCREEN SESSIONS (VICIdial daemons)
# =============================================================================
info "=== STEP 14: Starting VICIdial screen sessions ==="

START_SCREENS() {
  local name="$1"; shift
  screen -dmS "$name" bash -c "$*"
  info "  Started screen: $name"
}

# Start Asterisk
screen -dmS asterisk bash -c "asterisk -cvvvvvvvvvvvv 2>&1 | tee /var/log/asterisk/console.log"
sleep 3

# VICIdial core daemons (run in detached screens)
START_SCREENS "ASTupdate"   "/usr/share/astguiclient/AST_manager_listen.pl"
START_SCREENS "ASTsend"     "/usr/share/astguiclient/AST_send_action_child.pl"
START_SCREENS "ASTlisten"   "/usr/share/astguiclient/AST_manager_listen_VDAD.pl"
START_SCREENS "ASTVDauto"   "/usr/share/astguiclient/AST_VDauto_dial.pl"
START_SCREENS "ASTVDremote" "/usr/share/astguiclient/AST_VDremote_agents.pl"
START_SCREENS "ASTconf3way" "/usr/share/astguiclient/AST_conf_3way_recording.pl"
START_SCREENS "ASTVDadapt"  "/usr/share/astguiclient/AST_VDadaptive_dialer.pl"

info "All VICIdial screen sessions started."

# =============================================================================
# STEP 15 – FIREWALL (UFW)
# =============================================================================
info "=== STEP 15: Configuring UFW firewall ==="

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp comment "SSH"
# HTTP/HTTPS
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
# SIP
ufw allow 5060/udp comment "SIP"
ufw allow 5060/tcp comment "SIP-TCP"
# RTP range
ufw allow 10000:20000/udp comment "RTP"
# Asterisk AMI (local only)
ufw allow from 127.0.0.1 to any port 5038 comment "AMI-local"

ufw --force enable
info "Firewall configured."

# =============================================================================
# FINAL SERVICE START + STATUS
# =============================================================================
info "=== Final: Starting all services ==="

systemctl restart mariadb
systemctl restart apache2
systemctl enable asterisk 2>/dev/null || true

# Verify screens
sleep 2
SCREEN_COUNT=$(screen -ls 2>/dev/null | grep -c "Detached" || echo "0")
info "Active screen sessions: $SCREEN_COUNT"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   VICIdial Installation Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  Server IP      : ${YELLOW}${SERVER_IP}${NC}"
echo -e "  Asterisk ver   : ${YELLOW}${AST_VERSION}-vici${NC}"
echo -e "  VICIdial branch: ${YELLOW}SVN trunk (2.14 / version 9 series)${NC}"
echo ""
echo -e "  Admin GUI      : ${YELLOW}http://${SERVER_IP}/vicidial/admin.php${NC}"
echo -e "  Default login  : ${YELLOW}user: 6666  |  pass: 1234${NC}"
echo ""
echo -e "  MySQL root     : ${YELLOW}${MYSQL_ROOT_PASS}${NC}"
echo -e "  MySQL cron     : ${YELLOW}cron / ${MYSQL_CRON_PASS}${NC}"
echo -e "  MySQL custom   : ${YELLOW}custom / ${MYSQL_CUSTOM_PASS}${NC}"
echo ""
echo -e "  Log locations:"
echo -e "    Asterisk    : /var/log/asterisk/"
echo -e "    VICIdial    : /var/log/astguiclient/"
echo -e "    Apache      : /var/log/apache2/"
echo ""
echo -e "  Check screens  : ${YELLOW}screen -ls${NC}"
echo -e "  Attach screen  : ${YELLOW}screen -r <name>${NC}"
echo -e "  Asterisk CLI   : ${YELLOW}asterisk -rx 'core show version'${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT – Before going live:${NC}"
echo -e "  1. Change default MySQL passwords above"
echo -e "  2. Change VICIdial admin GUI password (user 6666)"
echo -e "  3. Configure your SIP trunk in /etc/asterisk/sip.conf"
echo -e "  4. Set your SERVER_IP in /etc/astguiclient.conf if NAT"
echo -e "  5. Open VICIdial GUI → Admin → Servers → add this server"
echo -e "  6. Open VICIdial GUI → Admin → Carriers → add SIP trunk"
echo -e "${GREEN}============================================================${NC}"
echo ""
