#!/bin/bash

set -e

install_backhaul() {
    local SRV_TYPE="$1"
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="386" ;;
        *) echo "Unsupported architecture!"; exit 1 ;;
    esac
    FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

    curl -L -o "$FILE_NAME" "https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main/$FILE_NAME" || curl -L -o "$FILE_NAME" "http://37.32.13.161/$FILE_NAME"

    mkdir -p /root/backhaul
    tar -xzf "$FILE_NAME" -C /root/backhaul && rm -f "$FILE_NAME"

    TUNNEL_PORT="3080"
    PORTS_RAW="8080,2086"
    PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/\",\"/g')
    BKTOKEN="default_token_123"

    if [ "$SRV_TYPE" = "server" ]; then
        BACKHAUL_CONFIG="[server]
bind_addr = \"0.0.0.0:$TUNNEL_PORT\"
transport = \"tcp\"
accept_udp = false
token = \"$BKTOKEN\"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = 2060
sniffer_log = \"/root/backhaul.json\"
log_level = \"info\"
ports = [\"$PORTS\"]"
    else
        IRAN_IP="37.32.13.161"
        BACKHAUL_CONFIG="[client]
remote_addr = \"$IRAN_IP:$TUNNEL_PORT\"
transport = \"tcp\"
token = \"$BKTOKEN\"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = 2060
sniffer_log = \"/root/backhaul.json\"
log_level = \"info\""
    fi

    echo "$BACKHAUL_CONFIG" > /root/backhaul/config.toml

    cat <<EOF | tee /etc/systemd/system/backhaul.service > /dev/null
[Unit]
Description=Backhaul Reverse Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/root/backhaul/backhaul -c /root/backhaul/config.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now backhaul.service
}

install_monitoring() {
    echo "---------------------------------------------------"
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

cat <<'EOM' > /root/backhaul_monitor.sh
#!/bin/bash

LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
RESTART_COUNT_FILE="/tmp/backhaul_restart_count"
TIME=$(date '+%Y-%m-%d %H:%M:%S')
TUNNEL_HOST="127.0.0.1"
TUNNEL_PORT="3080"

COUNT=$(cat $RESTART_COUNT_FILE 2>/dev/null || echo 0)

check_tcp() {
  nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT
}

check_ping() {
  ping -c1 -W1 $TUNNEL_HOST >/dev/null
}

check_http() {
  curl -s --connect-timeout 3 http://$TUNNEL_HOST:$TUNNEL_PORT >/dev/null
}

check_tls() {
  echo | openssl s_client -connect $TUNNEL_HOST:$TUNNEL_PORT -servername $TUNNEL_HOST -brief 2>/dev/null | grep -q 'Protocol'
}

STATUS_OK=true

if ! check_tcp; then
  echo "$TIME ❌ TCP check failed" >> $LOGFILE
  STATUS_OK=false
fi

if ! check_ping; then
  echo "$TIME ⚠️ Ping check failed" >> $LOGFILE
  STATUS_OK=false
fi

if ! check_http; then
  echo "$TIME 🚫 HTTP check failed" >> $LOGFILE
  STATUS_OK=false
fi

if ! check_tls; then
  echo "$TIME 🔒 TLS handshake failed" >> $LOGFILE
  STATUS_OK=false
fi

if ! $STATUS_OK; then
  echo "$TIME 🔄 Restarting $SERVICENAME (failure count=$COUNT)" >> $LOGFILE
  systemctl restart $SERVICENAME
  COUNT=$((COUNT+1))
else
  COUNT=0
  echo "$TIME ✅ All checks passed" >> $LOGFILE
fi

echo $COUNT > $RESTART_COUNT_FILE

if [ $COUNT -ge 3 ]; then
  echo "$TIME 🔁 3 failures detected, rebooting server..." >> $LOGFILE
  reboot
fi

tail -n 100 $LOGFILE > $LOGFILE.tmp && mv $LOGFILE.tmp $LOGFILE
EOM

chmod +x /root/backhaul_monitor.sh

cat <<EOF | sudo tee /etc/systemd/system/backhaul-monitor.service > /dev/null
[Unit]
Description=Backhaul Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
User=root
EOF

cat <<EOF | sudo tee /etc/systemd/system/backhaul-monitor.timer > /dev/null
[Unit]
Description=Run Backhaul Health Check every $MON_MIN minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=${MON_MIN}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now backhaul-monitor.timer
sudo systemctl restart backhaul-monitor.timer
sudo systemctl restart backhaul-monitor.service
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
echo "" > /var/log/backhaul_monitor.log
}


show_menu() {
    echo "==== BACKHAUL TOOL MENU ===="
    echo "1) Install Iran Server + Monitoring"
    echo "2) Install Foreign Server + Monitoring"
    echo "3) Install Only Monitoring"
    echo "4) View Monitoring Log (last 30 lines)"
    echo "5) View Backhaul Service Status"
    echo "0) Exit"
    echo "----------------------------"
    echo -n "Select an option: "
}

while true; do
    show_menu
    read -r opt
    case "$opt" in
        1)
            install_backhaul server
            install_monitoring
            ;;
        2)
            install_backhaul client
            install_monitoring
            ;;
        3)
            install_monitoring
            ;;
        4)
            tail -n 30 /var/log/backhaul_monitor.log || echo "No monitoring log yet."
            ;;
        5)
            systemctl status backhaul.service --no-pager | head -30
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option, try again." ;;
    esac
done
