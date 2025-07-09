#!/bin/bash

set -e

MY_GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main"
IRAN_URL="http://37.32.13.161"

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

    curl -L -o "$FILE_NAME" "$MY_GITHUB_URL/$FILE_NAME" || curl -L -o "$FILE_NAME" "$IRAN_URL/$FILE_NAME"

    mkdir -p /root/backhaul
    tar -xzf "$FILE_NAME" -C /root/backhaul && rm -f "$FILE_NAME"

    TUNNEL_PORT="3080"
    PORTS_RAW="8080,2086"
    PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/\",\"/g')
    BKTOKEN="default_token_123"
    TUN_SUBNET="10.10.10.0/24"

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
tun_name = \"backhaul\"
tun_subnet = \"$TUN_SUBNET\"
mtu = 1500
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
tun_name = \"backhaul\"
tun_subnet = \"$TUN_SUBNET\"
mtu = 1500
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
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}
    LOG_CHECK_MIN=$((MON_MIN * 3))

    read -p "IP ya hostname server moghabel: " TUNNEL_HOST
    read -p "Port tunnel server moghabel: " TUNNEL_PORT

cat <<EOM > /root/backhaul_monitor.sh
#!/bin/bash
LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
RESTART_FILE="/tmp/backhaul_restart_count"
TIME=\$(date '+%Y-%m-%d %H:%M:%S')

COUNT=\$(cat \$RESTART_FILE 2>/dev/null || echo 0)

STATUS_OK=true

if ! nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT; then
  echo "\$TIME ❌ TCP failed to $TUNNEL_HOST:$TUNNEL_PORT" >> \$LOGFILE
  STATUS_OK=false
fi

if ! ping -c1 -W1 $TUNNEL_HOST >/dev/null; then
  echo "\$TIME ⚠️ Ping failed to $TUNNEL_HOST" >> \$LOGFILE
  STATUS_OK=false
fi

if ! \$STATUS_OK; then
  echo "\$TIME 🔄 Restarting \$SERVICENAME (failure count=\$COUNT)" >> \$LOGFILE
  systemctl restart \$SERVICENAME
  COUNT=\$((COUNT+1))
else
  COUNT=0
  echo "\$TIME ✅ TCP+Ping passed for $TUNNEL_HOST:$TUNNEL_PORT" >> \$LOGFILE
fi

echo \$COUNT > \$RESTART_FILE

if [ \$COUNT -ge 3 ]; then
  echo "\$TIME 🔁 3 failures detected, rebooting..." >> \$LOGFILE
  reboot
fi

LAST_LOG_CHECK=\$(date --date=\"${LOG_CHECK_MIN} minutes ago\" '+%Y-%m-%d %H:%M')
if journalctl -u \$SERVICENAME --since \"\$LAST_LOG_CHECK\" | grep -q -E '(closed|shutting down|inactive)'; then
  echo "\$TIME ⚠️ Log issue detected in past ${LOG_CHECK_MIN} minutes" >> \$LOGFILE
  systemctl restart \$SERVICENAME
fi

tail -n 100 \$LOGFILE > \$LOGFILE.tmp && mv \$LOGFILE.tmp \$LOGFILE
EOM

chmod +x /root/backhaul_monitor.sh

cat <<EOF | tee /etc/systemd/system/backhaul-monitor.service > /dev/null
[Unit]
Description=Backhaul Monitoring Service

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
EOF

cat <<EOF | tee /etc/systemd/system/backhaul-monitor.timer > /dev/null
[Unit]
Description=Run Backhaul Monitoring every ${MON_MIN} minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=${MON_MIN}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now backhaul-monitor.timer
echo "✅ Monitoring configured for $TUNNEL_HOST:$TUNNEL_PORT every $MON_MIN minutes (log check every ${LOG_CHECK_MIN} min)"
}

show_menu() {
    echo "==== BACKHAUL TOOL MENU ===="
    echo "1) Install Iran Server + Monitoring"
    echo "2) Install Foreign Server + Monitoring"
    echo "3) Install Only Monitoring"
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
        0)
            exit 0
            ;;
        *)
            echo "Invalid option, try again." ;;
    esac
done
