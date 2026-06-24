#!/bin/bash
# =============================================================================
#  VICIDIAL FIRST-TIME SETUP SCRIPT
#  Creates: 2 Admin users, 3 Agent users, 3 US outbound campaigns
#  Run as root: sudo bash vicidial_setup.sh
# =============================================================================

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}";
            echo -e "${CYAN}  $*${NC}";
            echo -e "${CYAN}══════════════════════════════════════════════════${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash vicidial_setup.sh"

# =============================================================================
# CONFIGURATION — edit these before running
# =============================================================================
SERVER_IP=$(hostname -I | awk '{print $1}')
DB_USER="cron"
DB_PASS="1234"
DB_NAME="asterisk"
CARRIER_NAME="Twilio"
SIP_PEER="twilio"               # must match [twilio] in sip.conf

# Admin users
ADMIN1_USER="admin1"
ADMIN1_PASS="Admin@1234"
ADMIN1_NAME="Admin One"
ADMIN1_EMAIL="admin1@example.com"

ADMIN2_USER="admin2"
ADMIN2_PASS="Admin@5678"
ADMIN2_NAME="Admin Two"
ADMIN2_EMAIL="admin2@example.com"

# Agent users
AGENT1_USER="agent1"
AGENT1_PASS="Agent@1111"
AGENT1_NAME="Agent One"

AGENT2_USER="agent2"
AGENT2_PASS="Agent@2222"
AGENT2_NAME="Agent Two"

AGENT3_USER="agent3"
AGENT3_PASS="Agent@3333"
AGENT3_NAME="Agent Three"

# Campaigns
CAMP1_ID="SALES_US"
CAMP1_NAME="US Sales Campaign"
CAMP1_CID="12125550100"        # Your Twilio outbound CID (E.164 no +)

CAMP2_ID="LEADS_US"
CAMP2_NAME="US Leads Campaign"
CAMP2_CID="12125550101"

CAMP3_ID="FOLLOWUP_US"
CAMP3_NAME="US Follow-Up Campaign"
CAMP3_CID="12125550102"

# Dial prefix — must match your carrier setup in sip.conf
DIAL_PREFIX="SIP/twilio/"

# =============================================================================
section "STEP 1 — Verifying DB connection"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;" &>/dev/null \
  || error "Cannot connect to DB. Check DB_USER/DB_PASS in script."
info "DB connection OK."

# =============================================================================
section "STEP 2 — Creating Admin user group (if missing)"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT IGNORE INTO vicidial_user_groups (
  user_group, group_name, group_color,
  campaign_detail, ast_admin_access, ast_delete_admin,
  reports, report_email, load_leads, download_lists,
  scripts, hotkeys, scheduling, closer_campaigns,
  allowed_campaigns, allowed_inbound_groups,
  alter_agent_interface_options, email_only_campaigns,
  vicidial_recording_log, QC_enabled,
  agent_choose_ingroups, updates_from_db
) VALUES (
  'ADMIN','Administrator Group','#FF0000',
  '1','1','1','1','1','1','1','1','1','1','ALL','ALL','ALL',
  '1','1','1','1','1','1'
);

UPDATE vicidial_user_groups SET
  campaign_detail='1', ast_admin_access='1', ast_delete_admin='1',
  reports='1', report_email='1', load_leads='1', download_lists='1',
  scripts='1', hotkeys='1', scheduling='1', closer_campaigns='ALL',
  allowed_campaigns='ALL', allowed_inbound_groups='ALL',
  alter_agent_interface_options='1', email_only_campaigns='1',
  vicidial_recording_log='1', QC_enabled='1',
  agent_choose_ingroups='1', updates_from_db='1'
WHERE user_group='ADMIN';
SQL
info "Admin group ready."

# =============================================================================
section "STEP 3 — Creating Agent user group (if missing)"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT IGNORE INTO vicidial_user_groups (
  user_group, group_name, group_color,
  campaign_detail, ast_admin_access, ast_delete_admin,
  reports, report_email, load_leads, download_lists,
  scripts, hotkeys, scheduling, closer_campaigns,
  allowed_campaigns, allowed_inbound_groups
) VALUES (
  'AGENTS','Agent Group','#0000FF',
  '0','0','0','1','0','0','0','1','1','0','NONE','ALL','ALL'
);
SQL
info "Agent group ready."

# =============================================================================
section "STEP 4 — Creating Admin users"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL

-- Admin 1
INSERT INTO vicidial_users (
  user, pass, full_name, user_level, user_group, active,
  campaign_detail, ast_admin_access, ast_delete_admin,
  alter_agent_interface_options, closer_campaigns,
  allowed_campaigns, allowed_inbound_groups,
  load_leads, download_lists, scripts, reports,
  report_email, hotkeys, scheduling, email
) VALUES (
  '${ADMIN1_USER}','${ADMIN1_PASS}','${ADMIN1_NAME}','9','ADMIN','Y',
  '1','1','1','1','ALL','ALL','ALL',
  '1','1','1','1','1','1','1','${ADMIN1_EMAIL}'
)
ON DUPLICATE KEY UPDATE
  pass='${ADMIN1_PASS}', full_name='${ADMIN1_NAME}', user_level='9',
  user_group='ADMIN', active='Y', campaign_detail='1',
  ast_admin_access='1', ast_delete_admin='1',
  alter_agent_interface_options='1', closer_campaigns='ALL',
  allowed_campaigns='ALL', allowed_inbound_groups='ALL',
  load_leads='1', download_lists='1', scripts='1',
  reports='1', report_email='1', hotkeys='1', scheduling='1';

-- Admin 2
INSERT INTO vicidial_users (
  user, pass, full_name, user_level, user_group, active,
  campaign_detail, ast_admin_access, ast_delete_admin,
  alter_agent_interface_options, closer_campaigns,
  allowed_campaigns, allowed_inbound_groups,
  load_leads, download_lists, scripts, reports,
  report_email, hotkeys, scheduling, email
) VALUES (
  '${ADMIN2_USER}','${ADMIN2_PASS}','${ADMIN2_NAME}','9','ADMIN','Y',
  '1','1','1','1','ALL','ALL','ALL',
  '1','1','1','1','1','1','1','${ADMIN2_EMAIL}'
)
ON DUPLICATE KEY UPDATE
  pass='${ADMIN2_PASS}', full_name='${ADMIN2_NAME}', user_level='9',
  user_group='ADMIN', active='Y', campaign_detail='1',
  ast_admin_access='1', ast_delete_admin='1',
  alter_agent_interface_options='1', closer_campaigns='ALL',
  allowed_campaigns='ALL', allowed_inbound_groups='ALL',
  load_leads='1', download_lists='1', scripts='1',
  reports='1', report_email='1', hotkeys='1', scheduling='1';
SQL
info "Admin users created: $ADMIN1_USER / $ADMIN2_USER"

# =============================================================================
section "STEP 5 — Creating Agent users"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL

-- Agent 1
INSERT INTO vicidial_users (
  user, pass, full_name, user_level, user_group, active,
  allowed_campaigns, allowed_inbound_groups, scripts, hotkeys
) VALUES (
  '${AGENT1_USER}','${AGENT1_PASS}','${AGENT1_NAME}','1','AGENTS','Y',
  'ALL','ALL','1','1'
)
ON DUPLICATE KEY UPDATE
  pass='${AGENT1_PASS}', full_name='${AGENT1_NAME}',
  user_level='1', user_group='AGENTS', active='Y';

-- Agent 2
INSERT INTO vicidial_users (
  user, pass, full_name, user_level, user_group, active,
  allowed_campaigns, allowed_inbound_groups, scripts, hotkeys
) VALUES (
  '${AGENT2_USER}','${AGENT2_PASS}','${AGENT2_NAME}','1','AGENTS','Y',
  'ALL','ALL','1','1'
)
ON DUPLICATE KEY UPDATE
  pass='${AGENT2_PASS}', full_name='${AGENT2_NAME}',
  user_level='1', user_group='AGENTS', active='Y';

-- Agent 3
INSERT INTO vicidial_users (
  user, pass, full_name, user_level, user_group, active,
  allowed_campaigns, allowed_inbound_groups, scripts, hotkeys
) VALUES (
  '${AGENT3_USER}','${AGENT3_PASS}','${AGENT3_NAME}','1','AGENTS','Y',
  'ALL','ALL','1','1'
)
ON DUPLICATE KEY UPDATE
  pass='${AGENT3_PASS}', full_name='${AGENT3_NAME}',
  user_level='1', user_group='AGENTS', active='Y';
SQL
info "Agent users created: $AGENT1_USER / $AGENT2_USER / $AGENT3_USER"

# =============================================================================
section "STEP 6 — Creating Carrier (Twilio)"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO vicidial_carriers (
  carrier_id, carrier_name, active, protocol,
  registration_string, dialprefix,
  international_prefix, national_prefix,
  carrier_description
) VALUES (
  'TWILIO','${CARRIER_NAME}','Y','SIP',
  '','${DIAL_PREFIX}',
  '011','1',
  'Twilio SIP Trunk - US Outbound'
)
ON DUPLICATE KEY UPDATE
  carrier_name='${CARRIER_NAME}', active='Y',
  protocol='SIP', dialprefix='${DIAL_PREFIX}';
SQL
info "Carrier created: $CARRIER_NAME"

# =============================================================================
section "STEP 7 — Creating Server record"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO servers (
  server_ip, server_description, server_type,
  active, max_vicidial_trunks, asterisk_version,
  AMI_port, AMI_user, AMI_pass
) VALUES (
  '${SERVER_IP}','Primary ViciDial Server','asterisk',
  'Y','50','18',
  '5038','cron','${DB_PASS}'
)
ON DUPLICATE KEY UPDATE
  server_description='Primary ViciDial Server',
  active='Y', max_vicidial_trunks='50';
SQL
info "Server record created: $SERVER_IP"

# =============================================================================
section "STEP 8 — Creating 3 US Outbound Campaigns"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL

-- Campaign 1: US Sales
INSERT INTO vicidial_campaigns (
  campaign_id, campaign_name, active,
  dial_method, dial_level, auto_dial_level,
  campaign_cid, campaign_vdad_exten,
  dial_prefix, campaign_allow_inbound,
  am_message_exten, start_call_url,
  xferconf_a_dtmf, xferconf_b_dtmf,
  agent_pause_codes_active,
  no_hopper_leads_logins, dial_timeout,
  outbound_callurl, campaign_weight,
  available_only_ratio_tally,
  adaptive_intensity, adaptive_drop_limit,
  adaptive_maximum_level, adaptive_minimum_level,
  get_call_launch, dial_statuses,
  list_order_mix, campaign_language,
  campaign_recording, rec_filename,
  recording_filename, recording_variables,
  campaign_script, web_form_address,
  survey_method, survey_recording,
  closer_campaigns, campaign_calldate,
  campaign_login_seq, auto_pause_precall,
  ofcom_uk_rules, wrapup_seconds,
  pause_after_each_call, manual_dial_prefix
) VALUES (
  '${CAMP1_ID}','${CAMP1_NAME}','Y',
  'RATIO','1','1',
  '${CAMP1_CID}','8300',
  '${DIAL_PREFIX}','N',
  'dontcare','',
  '','',
  'N',
  '0','30',
  '','1',
  'N',
  '0','0',
  '10','1',
  'WEBFORM','NEW DROP NA',
  'DISABLED','en',
  'NEVER','',
  '','',
  '','',
  'NORMAL','',
  '','N',
  'N','0',
  'N','0','N',''
)
ON DUPLICATE KEY UPDATE
  campaign_name='${CAMP1_NAME}', active='Y',
  campaign_cid='${CAMP1_CID}', dial_prefix='${DIAL_PREFIX}';

-- Campaign 2: US Leads
INSERT INTO vicidial_campaigns (
  campaign_id, campaign_name, active,
  dial_method, dial_level, auto_dial_level,
  campaign_cid, campaign_vdad_exten,
  dial_prefix, campaign_allow_inbound,
  am_message_exten, get_call_launch,
  dial_statuses, list_order_mix,
  campaign_language, campaign_recording,
  dial_timeout, campaign_weight,
  ofcom_uk_rules, wrapup_seconds,
  pause_after_each_call, manual_dial_prefix
) VALUES (
  '${CAMP2_ID}','${CAMP2_NAME}','Y',
  'RATIO','1','1',
  '${CAMP2_CID}','8300',
  '${DIAL_PREFIX}','N',
  'dontcare','WEBFORM',
  'NEW DROP NA','DISABLED',
  'en','NEVER',
  '30','1',
  'N','0','N',''
)
ON DUPLICATE KEY UPDATE
  campaign_name='${CAMP2_NAME}', active='Y',
  campaign_cid='${CAMP2_CID}', dial_prefix='${DIAL_PREFIX}';

-- Campaign 3: US Follow-Up
INSERT INTO vicidial_campaigns (
  campaign_id, campaign_name, active,
  dial_method, dial_level, auto_dial_level,
  campaign_cid, campaign_vdad_exten,
  dial_prefix, campaign_allow_inbound,
  am_message_exten, get_call_launch,
  dial_statuses, list_order_mix,
  campaign_language, campaign_recording,
  dial_timeout, campaign_weight,
  ofcom_uk_rules, wrapup_seconds,
  pause_after_each_call, manual_dial_prefix
) VALUES (
  '${CAMP3_ID}','${CAMP3_NAME}','Y',
  'RATIO','1','1',
  '${CAMP3_CID}','8300',
  '${DIAL_PREFIX}','N',
  'dontcare','WEBFORM',
  'NEW DROP NA','DISABLED',
  'en','NEVER',
  '30','1',
  'N','0','N',''
)
ON DUPLICATE KEY UPDATE
  campaign_name='${CAMP3_NAME}', active='Y',
  campaign_cid='${CAMP3_CID}', dial_prefix='${DIAL_PREFIX}';
SQL
info "3 Campaigns created: $CAMP1_ID / $CAMP2_ID / $CAMP3_ID"

# =============================================================================
section "STEP 9 — Creating Lead Lists for each campaign"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL

INSERT INTO vicidial_lists (
  list_id, list_name, campaign_id, active,
  list_description, local_call_time,
  list_lastcalldate, expiration_date
) VALUES
  ('1001','Sales List','${CAMP1_ID}','Y','US Sales Leads','9am-9pm','2000-01-01 00:00:00','2035-01-01'),
  ('1002','Leads List','${CAMP2_ID}','Y','US Raw Leads','9am-9pm','2000-01-01 00:00:00','2035-01-01'),
  ('1003','Follow-Up List','${CAMP3_ID}','Y','US Follow-Up Leads','9am-9pm','2000-01-01 00:00:00','2035-01-01')
ON DUPLICATE KEY UPDATE
  list_name=VALUES(list_name),
  campaign_id=VALUES(campaign_id),
  active='Y';
SQL
info "Lead lists created (1001, 1002, 1003)"

# =============================================================================
section "STEP 10 — Assigning agents to all campaigns"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
UPDATE vicidial_users SET
  allowed_campaigns = 'ALL',
  closer_campaigns  = 'ALL',
  allowed_inbound_groups = 'ALL'
WHERE user IN ('${AGENT1_USER}','${AGENT2_USER}','${AGENT3_USER}',
               '${ADMIN1_USER}','${ADMIN2_USER}');
SQL
info "All users assigned to all campaigns."

# =============================================================================
section "STEP 11 — Creating agent phones (softphone extensions)"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL

INSERT INTO phones (
  extension, dialplan_number, voicemail_id,
  phone_password, status, active,
  phone_ip, computer_ip, server_ip,
  protocol, local_gmt
) VALUES
  ('8001','8001','8001','1234','active','Y','0.0.0.0','0.0.0.0','${SERVER_IP}','SIP','-5.00'),
  ('8002','8002','8002','1234','active','Y','0.0.0.0','0.0.0.0','${SERVER_IP}','SIP','-5.00'),
  ('8003','8003','8003','1234','active','Y','0.0.0.0','0.0.0.0','${SERVER_IP}','SIP','-5.00'),
  ('8004','8004','8004','1234','active','Y','0.0.0.0','0.0.0.0','${SERVER_IP}','SIP','-5.00'),
  ('8005','8005','8005','1234','active','Y','0.0.0.0','0.0.0.0','${SERVER_IP}','SIP','-5.00')
ON DUPLICATE KEY UPDATE
  status='active', active='Y', server_ip='${SERVER_IP}';
SQL
info "5 softphone extensions created: 8001-8005"

# =============================================================================
section "STEP 12 — Fixing original 6666 admin permissions"
# =============================================================================
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
UPDATE vicidial_users SET
  user_level='9', user_group='ADMIN', active='Y',
  campaign_detail='1', ast_admin_access='1', ast_delete_admin='1',
  alter_agent_interface_options='1', closer_campaigns='ALL',
  allowed_campaigns='ALL', allowed_inbound_groups='ALL',
  load_leads='1', download_lists='1', scripts='1',
  reports='1', report_email='1', hotkeys='1', scheduling='1'
WHERE user='6666';
SQL
info "Default 6666 admin permissions fixed."

# =============================================================================
section "STEP 13 — Reload Apache"
# =============================================================================
systemctl reload apache2
info "Apache reloaded."

# =============================================================================
section "VERIFICATION"
# =============================================================================
echo ""
info "Checking users..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  -e "SELECT user, full_name, user_level, user_group, active FROM vicidial_users WHERE user NOT IN ('6666') ORDER BY user_level DESC;"

echo ""
info "Checking campaigns..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  -e "SELECT campaign_id, campaign_name, active, dial_method, campaign_cid FROM vicidial_campaigns WHERE campaign_id IN ('${CAMP1_ID}','${CAMP2_ID}','${CAMP3_ID}');"

echo ""
info "Checking lists..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  -e "SELECT list_id, list_name, campaign_id, active FROM vicidial_lists WHERE list_id IN (1001,1002,1003);"

echo ""
info "Checking phones..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  -e "SELECT extension, status, active, server_ip FROM phones WHERE extension BETWEEN '8001' AND '8005';"

# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         VICIdial First-Time Setup Complete!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Admin GUI${NC}     → ${YELLOW}http://${SERVER_IP}/vicidial/admin.php${NC}"
echo -e "  ${CYAN}Agent GUI${NC}     → ${YELLOW}http://${SERVER_IP}/agc/vicidial.php${NC}"
echo ""
echo -e "  ${CYAN}━━━ ADMIN LOGINS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  user: ${YELLOW}${ADMIN1_USER}${NC}   pass: ${YELLOW}${ADMIN1_PASS}${NC}   (${ADMIN1_NAME})"
echo -e "  user: ${YELLOW}${ADMIN2_USER}${NC}   pass: ${YELLOW}${ADMIN2_PASS}${NC}   (${ADMIN2_NAME})"
echo -e "  user: ${YELLOW}6666${NC}        pass: ${YELLOW}test${NC}          (Original Admin)"
echo ""
echo -e "  ${CYAN}━━━ AGENT LOGINS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  user: ${YELLOW}${AGENT1_USER}${NC}   pass: ${YELLOW}${AGENT1_PASS}${NC}   ext: 8001"
echo -e "  user: ${YELLOW}${AGENT2_USER}${NC}   pass: ${YELLOW}${AGENT2_PASS}${NC}   ext: 8002"
echo -e "  user: ${YELLOW}${AGENT3_USER}${NC}   pass: ${YELLOW}${AGENT3_PASS}${NC}   ext: 8003"
echo ""
echo -e "  ${CYAN}━━━ CAMPAIGNS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${YELLOW}${CAMP1_ID}${NC}    → ${CAMP1_NAME}  (CID: ${CAMP1_CID})  List: 1001"
echo -e "  ${YELLOW}${CAMP2_ID}${NC}    → ${CAMP2_NAME}  (CID: ${CAMP2_CID})  List: 1002"
echo -e "  ${YELLOW}${CAMP3_ID}${NC} → ${CAMP3_NAME}  (CID: ${CAMP3_CID})  List: 1003"
echo ""
echo -e "  ${CYAN}━━━ NEXT STEPS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  1. Update CAMP CIDs above with your real Twilio numbers"
echo -e "  2. Upload leads via Admin → Lists → select list → Import Leads"
echo -e "  3. Start campaign: Admin → Campaigns → START"
echo -e "  4. Agents login at Agent GUI with ext 8001-8003, pass 1234"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""
