#!/bin/bash
# =============================================================================
#  RESUME SCRIPT – Asterisk 18.21.0-vici + VICIdial SVN trunk
#  Run this AFTER fix_apache.sh has succeeded.
#
#  sudo bash install_asterisk_vicidial.sh 2>&1 | tee /var/log/ast_vici_install.log
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"; \
            echo -e "${CYAN}  $*${NC}"; \
            echo -e "${CYAN}══════════════════════════════════════════════════${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash install_asterisk_vicidial.sh"

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
AST_CONF="/etc/asterisk"
VICI_SHARE="/usr/share/astguiclient"
AGI_BIN="/var/lib/asterisk/agi-bin"
RTP_START=10000
RTP_END=20000

info "Server IP : $SERVER_IP"
info "Asterisk  : $AST_VERSION-vici"

# =============================================================================
# STEP A – ASTERISK USER
# =============================================================================
section "STEP A – Asterisk system user"

id asterisk &>/dev/null \
  || useradd -r -d /var/lib/asterisk -s /sbin/nologin -c "Asterisk PBX" asterisk
usermod -aG audio asterisk 2>/dev/null || true
info "Asterisk user ready."

# =============================================================================
# STEP B – EXTRA BUILD DEPENDENCIES (in case any were missed)
# =============================================================================
section "STEP B – Ensuring all build dependencies are present"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y \
  build-essential gcc g++ make automake autoconf libtool pkg-config \
  libssl-dev libncurses5-dev libnewt-dev libxml2-dev libsqlite3-dev \
  libjansson-dev uuid-dev libedit-dev libsrtp2-dev libogg-dev \
  libvorbis-dev libcurl4-openssl-dev libgmime-3.0-dev unixodbc-dev \
  liblua5.2-dev libopus-dev libspeex-dev libspeexdsp-dev \
  libgnutls28-dev liburiparser-dev libresample1-dev \
  zlib1g-dev libreadline-dev libasound2-dev libpopt-dev \
  subversion wget sox lame mpg123 screen 2>/dev/null
info "Dependencies confirmed."

# =============================================================================
# STEP C – COMPILE ASTERISK 18.21.0-vici
# =============================================================================
section "STEP C – Downloading and compiling Asterisk $AST_VERSION-vici"

# Clean any partial previous attempt
find "$AST_SRC" -maxdepth 1 -name "asterisk-${AST_VERSION}*" -exec rm -rf {} + 2>/dev/null || true

cd "$AST_SRC"

info "Downloading $AST_TARBALL ..."
wget -q --show-progress \
  "${VICI_DOWNLOAD_BASE}/${AST_TARBALL}" \
  -O "${AST_TARBALL}" \
  || error "Download failed – check internet: wget ${VICI_DOWNLOAD_BASE}/${AST_TARBALL}"

info "Extracting ..."
tar -xzf "${AST_TARBALL}"
cd "asterisk-${AST_VERSION}-vici"

info "Running install_prereq (installs remaining build deps) ..."
./contrib/scripts/install_prereq install

info "Running bootstrap.sh ..."
./bootstrap.sh

info "Running configure ..."
./configure \
  --libdir=/usr/lib \
  --with-gsm=internal \
  --enable-opus \
  --enable-srtp \
  --with-ssl \
  --with-pjproject-bundled \
  2>&1 | tail -10

info "Selecting modules via menuselect ..."
make menuselect.makeopts
menuselect/menuselect \
  --enable chan_sip \
  --enable res_srtp \
  --enable codec_opus \
  --enable format_mp3 \
  --enable app_meetme \
  --enable app_queue \
  --enable app_voicemail \
  --enable app_confbridge \
  --enable app_transfer \
  --enable cdr_mysql \
  --enable cdr_csv \
  --enable res_musiconhold \
  --enable CORE-SOUNDS-EN-GSM \
  --enable CORE-SOUNDS-EN-ULAW \
  --enable EXTRA-SOUNDS-EN-GSM \
  --enable EXTRA-SOUNDS-EN-ULAW \
  --disable BUILD_NATIVE \
  menuselect.makeopts

info "Compiling with $(nproc) CPU cores (10-20 minutes) ..."
make -j"$(nproc)"

info "Installing Asterisk ..."
make install
make config
make samples

# Fix runuser
if [[ -f /etc/default/asterisk ]]; then
  sed -i 's/^#AST_USER.*/AST_USER="asterisk"/'   /etc/default/asterisk
  sed -i 's/^#AST_GROUP.*/AST_GROUP="asterisk"/' /etc/default/asterisk
fi

info "Asterisk $AST_VERSION compiled and installed."

# =============================================================================
# STEP D – SOUNDS
# =============================================================================
section "STEP D – Asterisk sounds (GSM + ULAW + MOH)"

SOUNDS_DIR="/var/lib/asterisk/sounds"
MOH_DIR="/var/lib/asterisk/sounds/moh"
mkdir -p "$SOUNDS_DIR" "$MOH_DIR"
cd "$AST_SRC"

for SOUND_TGZ in \
  asterisk-core-sounds-en-gsm-current.tar.gz \
  asterisk-core-sounds-en-ulaw-current.tar.gz \
  asterisk-extra-sounds-en-gsm-current.tar.gz \
  asterisk-extra-sounds-en-ulaw-current.tar.gz \
  asterisk-moh-freeplay-gsm.tar.gz \
  asterisk-moh-freeplay-ulaw.tar.gz \
  asterisk-moh-opsound-gsm-current.tar.gz
do
  info "  $SOUND_TGZ ..."
  wget -q --show-progress "${VICI_DOWNLOAD_BASE}/${SOUND_TGZ}" -O "$SOUND_TGZ" \
    && tar -xzf "$SOUND_TGZ" -C "$SOUNDS_DIR" \
    || warn "  Skipping $SOUND_TGZ (not critical)"
done

chown -R asterisk:asterisk "$SOUNDS_DIR"
info "Sounds installed."

# =============================================================================
# STEP E – ASTERISK-PERL
# =============================================================================
section "STEP E – asterisk-perl 0.08"

cd "$AST_SRC"
wget -q --show-progress "${VICI_DOWNLOAD_BASE}/asterisk-perl-0.08.tar.gz" \
  -O asterisk-perl-0.08.tar.gz
tar -xzf asterisk-perl-0.08.tar.gz
cd asterisk-perl-0.08
perl Makefile.PL && make && make install
info "asterisk-perl installed."

# =============================================================================
# STEP F – FULL ASTERISK CONFIG FILES
# =============================================================================
section "STEP F – Writing Asterisk configuration files"

mkdir -p "$AST_CONF"

# rtp.conf
cat > "$AST_CONF/rtp.conf" <<RTPCONF
[general]
rtpstart=${RTP_START}
rtpend=${RTP_END}
strictrtp=no
icesupport=no
RTPCONF

# sip.conf
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
allow=alaw
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
progressinband=no
videosupport=no
maxexpiry=3600
defaultexpiry=3600
dtmfmode=rfc2833
relaxdtmf=yes
alwaysauthreject=yes
canreinvite=no
;
; ── Add your SIP trunk below ──────────────────────────────
; [MY_TRUNK]
; type=peer
; host=sip.yourprovider.com
; username=YOUR_USER
; secret=YOUR_SECRET
; fromuser=YOUR_USER
; fromdomain=sip.yourprovider.com
; insecure=port,invite
; dtmfmode=rfc2833
; disallow=all
; allow=ulaw
; context=default
; ──────────────────────────────────────────────────────────
SIPCONF

# extensions.conf
cat > "$AST_CONF/extensions.conf" <<'EXTCONF'
[general]
static=yes
writeprotect=no

[globals]
AGENTEXTEN=8300
VMAIL_SERVER=localhost

#include "extensions_vici.conf"
EXTCONF

touch "$AST_CONF/extensions_vici.conf"

# manager.conf
cat > "$AST_CONF/manager.conf" <<AMICONF
[general]
enabled=yes
port=5038
bindaddr=127.0.0.1
timestampevents=yes

[cron]
secret=${MYSQL_CRON_PASS}
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.0
read=system,call,log,verbose,command,agent,user,originate,cdr,dialplan
write=system,call,log,verbose,command,agent,user,originate,cdr,dialplan

[custom]
secret=${MYSQL_CUSTOM_PASS}
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.0
read=system,call,log,verbose,command,agent,user,originate,cdr,dialplan
write=system,call,log,verbose,command,agent,user,originate,cdr,dialplan
AMICONF

# modules.conf – force chan_sip, disable pjsip
cat > "$AST_CONF/modules.conf" <<'MODCONF'
[modules]
autoload=yes
noload=chan_pjsip.so
noload=res_pjsip.so
noload=res_pjsip_session.so
load=chan_sip.so
load=app_meetme.so
load=app_queue.so
load=app_voicemail.so
load=res_musiconhold.so
load=cdr_mysql.so
load=res_srtp.so
MODCONF

# musiconhold.conf
cat > "$AST_CONF/musiconhold.conf" <<'MOHCONF'
[general]
cachertclasses=yes

[default]
mode=files
directory=/var/lib/asterisk/sounds/moh
random=yes
MOHCONF

# voicemail.conf
cat > "$AST_CONF/voicemail.conf" <<'VMCONF'
[general]
format=wav49|gsm|wav
attach=yes
maxlogins=3
emaildateformat=%A, %B %d, %Y at %r

[default]
VMCONF

# features.conf
cat > "$AST_CONF/features.conf" <<'FEATCONF'
[general]
pickupexten=*8
featuredigittimeout=500
transferdigittimeout=3000

[featuremap]
blindxfer=##
atxfer=*2
disconnect=*0
automon=*1
FEATCONF

# logger.conf
cat > "$AST_CONF/logger.conf" <<'LOGCONF'
[general]
appendhostname=no
queue_log=yes
rotatestrategy=rotate

[logfiles]
console  => notice,warning,error,verbose
messages => notice,warning,error
full     => notice,warning,error,debug,verbose,dtmf,fax
queue_log => queue_log
LOGCONF

# cdr.conf
cat > "$AST_CONF/cdr.conf" <<'CDRCONF'
[general]
enable=yes
unanswered=yes

[csv]
usegmtime=no
loguniqueid=yes
CDRCONF

# cdr_mysql.conf
cat > "$AST_CONF/cdr_mysql.conf" <<CDRMYSQL
[global]
hostname=localhost
dbname=asterisk
table=cdr
password=${MYSQL_CRON_PASS}
user=cron
port=3306
CDRMYSQL

# indications.conf
cat > "$AST_CONF/indications.conf" <<'INDCONF'
[general]
country=us
INDCONF

# Create all runtime directories
for dir in \
  /var/log/astguiclient \
  /var/spool/asterisk/monitor \
  /var/spool/asterisk/monitorDONE \
  /var/spool/asterisk/tmp \
  /var/spool/asterisk/meetme \
  /var/lib/asterisk/sounds/moh \
  /var/run/asterisk; do
  mkdir -p "$dir"
done

# Fix ownership
chown -R asterisk:asterisk "$AST_CONF"
chown -R asterisk:asterisk /var/lib/asterisk
chown -R asterisk:asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/spool/asterisk
chown -R asterisk:asterisk /var/run/asterisk
chown -R asterisk:asterisk /var/log/astguiclient

info "All Asterisk config files written."

# =============================================================================
# STEP G – VICIDIAL SVN CHECKOUT
# =============================================================================
section "STEP G – VICIdial SVN trunk checkout"

# Clean old checkout if any
rm -rf "$VICI_SRC" 2>/dev/null || true
mkdir -p "$VICI_SRC"
cd "$VICI_SRC"

info "Checking out SVN trunk (this may take a few minutes) ..."
svn checkout "$SVN_REPO" trunk \
  || error "SVN failed. Try alternate: svn checkout http://svn.eflo.net:8880/agc_2-X/trunk trunk"

info "VICIdial source at: $VICI_SRC/trunk"

# =============================================================================
# STEP H – DEPLOY VICIDIAL FILES
# =============================================================================
section "STEP H – Deploying VICIdial files"

mkdir -p "$VICI_SHARE"
cp -r "$VICI_SRC/trunk/"* "$VICI_SHARE/" 2>/dev/null || true

# AGI scripts
mkdir -p "$AGI_BIN"
find "$VICI_SHARE" -maxdepth 4 \( -name "*.agi" -o -name "*.pl" \) \
  -exec cp -f {} "$AGI_BIN/" \; 2>/dev/null || true
chmod 755 "$AGI_BIN/"* 2>/dev/null || true
chown -R asterisk:asterisk "$AGI_BIN"

# Make all scripts executable
find "$VICI_SHARE" -name "*.pl"  -exec chmod +x {} \;
find "$VICI_SHARE" -name "*.agi" -exec chmod +x {} \;

info "VICIdial files deployed to $VICI_SHARE"

# =============================================================================
# STEP I – DATABASE IMPORT
# =============================================================================
section "STEP I – Importing VICIdial database schema"

SQL_FILE=$(find "$VICI_SRC/trunk" -maxdepth 4 \
  \( -name "VDCL*.sql" -o -name "VICIdial*.sql" -o -name "asterisk*.sql" \) \
  | grep -v sample | head -1)

if [[ -n "$SQL_FILE" ]]; then
  info "Importing: $SQL_FILE"
  mysql -u root -p"${MYSQL_ROOT_PASS}" asterisk < "$SQL_FILE"
  info "Database import complete."
else
  warn "No single SQL file found – trying all .sql files ..."
  find "$VICI_SRC/trunk" -maxdepth 5 -name "*.sql" | sort | while read -r sqlf; do
    info "  Importing: $sqlf"
    mysql -u root -p"${MYSQL_ROOT_PASS}" asterisk < "$sqlf" 2>/dev/null || true
  done
fi

# Run installer script if present
INSTALL_PL=$(find "$VICI_SRC/trunk" -maxdepth 3 -name "VICIDIAL_install.pl" | head -1)
if [[ -n "$INSTALL_PL" ]]; then
  info "Running: $INSTALL_PL"
  perl "$INSTALL_PL" 2>&1 || warn "Installer warnings above."
fi

# Copy VICIdial's extensions_vici.conf into Asterisk
VICI_EXT=$(find "$VICI_SHARE" -maxdepth 4 -name "extensions_vici.conf" 2>/dev/null | head -1)
if [[ -n "$VICI_EXT" ]]; then
  cp "$VICI_EXT" "$AST_CONF/extensions_vici.conf"
  info "Copied extensions_vici.conf into $AST_CONF"
fi

# =============================================================================
# STEP J – /etc/astguiclient.conf
# =============================================================================
section "STEP J – /etc/astguiclient.conf"

cat > /etc/astguiclient.conf <<AGICCONF
# VICIdial AGI client configuration – $(date)

PATHhome=${VICI_SHARE}
PATHlogs=/var/log/astguiclient
PATHagi=${AGI_BIN}
PATHweb=${VICI_SHARE}/vicidial
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
VARREPORT_host=localhost
AGICCONF

chmod 640 /etc/astguiclient.conf
info "/etc/astguiclient.conf written."

# =============================================================================
# STEP K – CRON JOBS
# =============================================================================
section "STEP K – VICIdial cron jobs"

CRON_FILE="/var/spool/cron/crontabs/root"
mkdir -p /var/spool/cron/crontabs

# Remove old VICIdial entries to prevent duplicates
if [[ -f "$CRON_FILE" ]]; then
  grep -v "astguiclient" "$CRON_FILE" > /tmp/cron_clean || true
  cp /tmp/cron_clean "$CRON_FILE"
fi

cat >> "$CRON_FILE" <<'CRONEOF'
MAILTO=""
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q
1 1,7 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug --postal-code-gmt
3 1 * * * /usr/share/astguiclient/AST_DB_optimize.pl
2 0 * * 0 /usr/share/astguiclient/AST_agent_week.pl
22 0 * * * /usr/share/astguiclient/AST_agent_day.pl
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl
50 0 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --GSM
24 0 * * * /usr/bin/find /var/spool/asterisk/monitor -maxdepth 2 -type f -mtime +7 -print | xargs rm -f
24 0 * * * /usr/bin/find /var/spool/asterisk/monitorDONE -maxdepth 2 -type f -mtime +7 -print | xargs rm -f
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
28 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
CRONEOF

chmod 600 "$CRON_FILE"
chown root:crontab "$CRON_FILE" 2>/dev/null || true
crontab "$CRON_FILE"
info "Cron jobs installed."

# =============================================================================
# STEP L – RC.LOCAL (auto-start on reboot)
# =============================================================================
section "STEP L – /etc/rc.local auto-start"

cat > /etc/rc.local <<'RCLOCAL'
#!/bin/bash
sleep 10
screen -dmS asterisk   bash -c "asterisk -cvvvvvvvvvvvv 2>&1 | tee /var/log/asterisk/console.log"
sleep 5
screen -dmS ASTupdate   bash -c "/usr/share/astguiclient/AST_manager_listen.pl"
screen -dmS ASTsend     bash -c "/usr/share/astguiclient/AST_send_action_child.pl"
screen -dmS ASTlisten   bash -c "/usr/share/astguiclient/AST_manager_listen_VDAD.pl"
screen -dmS ASTVDauto   bash -c "/usr/share/astguiclient/AST_VDauto_dial.pl"
screen -dmS ASTVDremote bash -c "/usr/share/astguiclient/AST_VDremote_agents.pl"
screen -dmS ASTconf3way bash -c "/usr/share/astguiclient/AST_conf_3way_recording.pl"
screen -dmS ASTVDadapt  bash -c "/usr/share/astguiclient/AST_VDadaptive_dialer.pl"
exit 0
RCLOCAL

chmod +x /etc/rc.local
systemctl enable rc-local 2>/dev/null || true
info "rc.local configured."

# =============================================================================
# STEP M – START ASTERISK + VICIDIAL DAEMONS
# =============================================================================
section "STEP M – Starting Asterisk and VICIdial daemons"

# Kill any orphan asterisk processes
pkill -f asterisk 2>/dev/null || true
sleep 2

# Start Asterisk in a screen session
screen -dmS asterisk bash -c "asterisk -cvvvvvvvvvvvv 2>&1 | tee /var/log/asterisk/console.log"
info "Waiting 8 seconds for Asterisk to fully start ..."
sleep 8

# Verify Asterisk
if asterisk -rx "core show version" &>/dev/null; then
  AST_VER=$(asterisk -rx "core show version" 2>/dev/null)
  info "✔  Asterisk running: $AST_VER"
else
  warn "Asterisk not responding yet – check: screen -r asterisk"
fi

# Start VICIdial daemons
DAEMONS=(
  "ASTupdate:/usr/share/astguiclient/AST_manager_listen.pl"
  "ASTsend:/usr/share/astguiclient/AST_send_action_child.pl"
  "ASTlisten:/usr/share/astguiclient/AST_manager_listen_VDAD.pl"
  "ASTVDauto:/usr/share/astguiclient/AST_VDauto_dial.pl"
  "ASTVDremote:/usr/share/astguiclient/AST_VDremote_agents.pl"
  "ASTconf3way:/usr/share/astguiclient/AST_conf_3way_recording.pl"
  "ASTVDadapt:/usr/share/astguiclient/AST_VDadaptive_dialer.pl"
)

for entry in "${DAEMONS[@]}"; do
  NAME="${entry%%:*}"
  CMD="${entry##*:}"
  if [[ -f "$CMD" ]]; then
    screen -dmS "$NAME" bash -c "$CMD"
    info "  ✔ Started screen: $NAME"
  else
    warn "  ✘ Script missing: $CMD  (check SVN checkout)"
  fi
done

sleep 3
SCREEN_COUNT=$(screen -ls 2>/dev/null | grep -c "Detached" || echo 0)
info "Active screen sessions: $SCREEN_COUNT"

# =============================================================================
# STEP N – VERIFICATION
# =============================================================================
section "STEP N – Verification checks"

PASS=0; FAIL=0
check() {
  if eval "$2" &>/dev/null; then
    echo -e "  ${GREEN}✔${NC}  $1"; ((PASS++))
  else
    echo -e "  ${RED}✘${NC}  $1"; ((FAIL++))
  fi
}

check "Asterisk binary installed"      "test -x /usr/sbin/asterisk"
check "Asterisk is running"            "asterisk -rx 'core show version'"
check "chan_sip loaded"                "asterisk -rx 'module show like chan_sip' | grep -q chan_sip"
check "app_meetme loaded"              "asterisk -rx 'module show like app_meetme' | grep -q meetme"
check "SIP port 5060 listening"        "ss -ulnp | grep -q 5060"
check "AMI port 5038 listening"        "ss -tlnp | grep -q 5038"
check "VICIdial share exists"          "test -d $VICI_SHARE/vicidial"
check "AGI scripts present"            "ls $AGI_BIN/*.pl &>/dev/null"
check "astguiclient.conf present"      "test -f /etc/astguiclient.conf"
check "asterisk DB reachable"          "mysql -u cron -p'${MYSQL_CRON_PASS}' -e 'USE asterisk;'"
check "Apache serving /vicidial"       "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/vicidial/admin.php | grep -qE '200|302'"
check "Screen sessions running"        "screen -ls | grep -q Detached"
check "Cron jobs installed"            "crontab -l | grep -q astguiclient"

echo ""
echo -e "  ${GREEN}${PASS} passed${NC}  |  ${RED}${FAIL} failed${NC}"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Asterisk + VICIdial Installation Complete!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Asterisk version : ${YELLOW}${AST_VERSION}-vici${NC}"
echo -e "  Server IP        : ${YELLOW}${SERVER_IP}${NC}"
echo ""
echo -e "  ${CYAN}Admin GUI${NC}  → ${YELLOW}http://${SERVER_IP}/vicidial/admin.php${NC}"
echo -e "  ${CYAN}Agent GUI${NC}  → ${YELLOW}http://${SERVER_IP}/agc/vicidial.php${NC}"
echo -e "  ${CYAN}Login${NC}      → ${YELLOW}user: 6666  |  pass: 1234${NC}"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "    screen -ls                         # all running daemons"
echo -e "    screen -r asterisk                 # Asterisk console"
echo -e "    asterisk -rx 'core show version'   # confirm Asterisk"
echo -e "    asterisk -rx 'sip show peers'      # SIP peers"
echo -e "    asterisk -rx 'module show like chan_sip'"
echo ""
echo -e "  ${YELLOW}Next steps in VICIdial GUI:${NC}"
echo -e "    1. Admin → Servers → Add this server (IP: ${SERVER_IP})"
echo -e "    2. Admin → Carriers → Add your SIP trunk"
echo -e "    3. Admin → Phones  → Add agent phones"
echo -e "    4. Admin → Campaigns → Create a campaign"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

