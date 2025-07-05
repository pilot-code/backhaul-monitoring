#!/bin/bash

#=======================
# Backhaul Mother Script v1.2 (Complete)
#=======================

# Color Functions
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

function show_menu() {
  echo -e "${CYAN}==============================="
  echo "      Backhaul Setup Menu"
  echo -e   "===============================${NC}"
  echo -e "${YELLOW}1.${NC} Nasb Server Iran \xf0\x9f\x87\xae\xf0\x9f\x87\xb7"
  echo -e "${YELLOW}2.${NC} Nasb Server Kharej \xf0\x9f\x8c\x8d"
  echo -e "${YELLOW}3.${NC} Monitoring DoTarafe \xf0\x9f\x94\x84"
  echo -e "${YELLOW}4.${NC} Namayesh Log \xf0\x9f\x93\x9c"
  echo -e "${YELLOW}5.${NC} Vaziyat Service-ha \xf0\x9f\x93\x8a"
  echo -e "${YELLOW}6.${NC} Fast Reconnect \xe2\x9a\xa1"
  echo -e "${YELLOW}7.${NC} Uninstall Kamel \xf0\x9f\x97\x91\xef\xb8\x8f"
  echo -e "${YELLOW}8.${NC} Khorooj \xe2\x9d\x8c"
}

function read_with_default() {
  local prompt="$1"
  local default="$2"
  read -p "$prompt [$default]: " input
  echo "${input:-$default}"
}

function install_server_iran() {
  echo -e "\n--- Nasb Server Iran ---"
  PORT=$(read_with_default "Port Tunnel" "3080")
  TOKEN=$(read_with_default "Token" "default_token_123")
  SUBNET=$(read_with_default "TUN Subnet" "10.10.10.0/24")
  MTU=$(read_with_default "MTU" "1500")
  PORTS=$(read_with_default "Ports (masalan: 8080,2086)" "8080,2086")

  cat > /etc/backhaul_server.toml <<EOF
[server]
bind_addr = ":$PORT"
transport = "tcp"
accept_udp = false
token = "$TOKEN"
keepalive_period = 20
nodelay = false
channel_size = 2048
heartbeat = 20
mux_con = 8
mux_version = 2
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 2000000
sniffer = false
web_port = 0
sniffer_log = "/root/log.json"
log_level = "info"
proxy_protocol= false
tun_name = "backhaul"
tun_subnet = "$SUBNET"
mtu = $MTU
ports = [${PORTS//,/","}]
EOF

  echo "✅ File backhaul_server.toml sakhte shod."
}

function install_server_kharej() {
  echo -e "\n--- Nasb Server Kharej ---"
  REMOTE=$(read_with_default "IP:PORT Server Iran" "37.32.10.53:3080")
  TOKEN=$(read_with_default "Token" "default_token_123")
  SUBNET=$(read_with_default "TUN Subnet" "10.10.10.0/24")
  MTU=$(read_with_default "MTU" "1500")

  cat > /etc/backhaul_client.toml <<EOF
[client]
remote_addr = "$REMOTE"
transport = "tcp"
token = "$TOKEN"
connection_pool = 24
aggressive_pool = false
keepalive_period = 20
nodelay = true
retry_interval = 3
dial_timeout = 10
mux_version = 2
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 2000000
sniffer = false
web_port = 0
sniffer_log = "/root/log.json"
log_level = "info"
ip_limit= false
tun_name = "backhaul"
tun_subnet = "$SUBNET"
mtu = $MTU
EOF

  echo "✅ File backhaul_client.toml sakhte shod."
}

function install_monitoring() {
  echo -e "\n--- Nasb Monitoring DoTarafe ---"
  INTERVAL_MIN=$(read_with_default "Har chand daghighe yebar check kone?" "1")

  cat > /root/backhaul_monitor.sh <<'EOM'
#!/bin/bash
LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"
CHECKTIME=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=$(systemctl is-active $SERVICENAME)
STATUS_DETAIL=$(systemctl status $SERVICENAME --no-pager | head -30)
LAST_CHECK=$(date --date='1 minute ago' '+%Y-%m-%d %H:%M')

if [ -f /var/run/reboot-required ]; then
  echo "$CHECKTIME 🔁 System requires reboot. Rebooting now..." >> $LOGFILE
  sleep 5
  reboot
fi

journalctl -u $SERVICENAME --since "$LAST_CHECK:00" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > $TMP_LOG

if [ "$STATUS" != "active" ]; then
  echo "$CHECKTIME ❌ $SERVICENAME is DOWN! [status: $STATUS]" >> $LOGFILE
  echo "$CHECKTIME ❗ Trying to restart $SERVICENAME..." >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo "$CHECKTIME 🔄 Restart command successful." >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo "$CHECKTIME 🟢 Status after restart: $NEW_STATUS" >> $LOGFILE
  else
    echo "$CHECKTIME 🚫 ERROR: Restart command FAILED!" >> $LOGFILE
  fi
elif [ -s $TMP_LOG ]; then
  echo "$CHECKTIME ⚠️ Issue detected in recent log:" >> $LOGFILE
  cat $TMP_LOG >> $LOGFILE
  echo "$CHECKTIME ❗ Trying to restart $SERVICENAME..." >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo "$CHECKTIME 🔄 Restart command successful." >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo "$CHECKTIME 🟢 Status after restart: $NEW_STATUS" >> $LOGFILE
  else
    echo "$CHECKTIME 🚫 ERROR: Restart command FAILED!" >> $LOGFILE
  fi
else
  echo "$CHECKTIME ✅ Backhaul healthy. [status: $STATUS]" >> $LOGFILE
fi

echo "---- [ $CHECKTIME : systemctl status $SERVICENAME ] ----" > /var/log/backhaul_status_last.log
echo "$STATUS_DETAIL" >> /var/log/backhaul_status_last.log

rm -f $TMP_LOG

if [ -f "$LOGFILE" ]; then
  tail -n 100 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
fi
tail -n 35 /var/log/backhaul_status_last.log > /var/log/backhaul_status_last.log.tmp && mv /var/log/backhaul_status_last.log.tmp /var/log/backhaul_status_last.log
EOM

  chmod +x /root/backhaul_monitor.sh

  cat > /etc/systemd/system/backhaul-monitor.service <<EOF
[Unit]
Description=Backhaul Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
User=root
EOF

  cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Run Backhaul Health Check every $INTERVAL_MIN minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=${INTERVAL_MIN}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now backhaul-monitor.timer
  systemctl restart backhaul-monitor.timer
  systemctl restart backhaul-monitor.service
  journalctl --rotate
  journalctl --vacuum-time=1s
  echo "" > /var/log/backhaul_monitor.log

  echo "✅ Monitoring doTarafe ba movafaghiat nasb shod."
}

function main_menu() {
  while true; do
    show_menu
    read -p "Lotfan adad mored nazar ro vared konid: " choice
    case $choice in
      1) install_server_iran;;
      2) install_server_kharej;;
      3) install_monitoring;;
      4) tail -n 30 /var/log/backhaul_monitor.log;;
      5) cat /var/log/backhaul_status_last.log;;
      6) echo "⚡ Fast Reconnect (dar hale sazandegi)";;
      7) echo "🗑️ Uninstall (dar hale sazandegi)";;
      8) echo "Khorooj az script..."; break;;
      *) echo "❗ Adad vared shode eshtebah ast.";;
    esac
    echo ""
  done
}

main_menu
