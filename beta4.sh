#!/bin/bash

set -e

MY_GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main"
IRAN_URL="http://37.32.13.161"

show_menu() {
    echo "==== BACKHAUL TOOL MENU ===="
    echo "1) Install Iran Server (Backhaul + Monitoring)"
    echo "2) Install Foreign Server (Backhaul + Monitoring)"
    echo "3) Install Only Monitoring"
    echo "4) Check Monitoring Log"
    echo "5) Check Backhaul Service Status"
    echo "0) Exit"
    echo "----------------------------"
    echo -n "Select an option: "
}

check_monitor_log() {
    echo "---- Last 30 lines of monitoring log ----"
    if [ -f /var/log/backhaul_monitor.log ]; then
        tail -n 30 /var/log/backhaul_monitor.log
    else
        echo "No monitor log found!"
    fi
    echo
}

check_service_status() {
    echo "---- Backhaul systemctl status (short) ----"
    if [ -f /var/log/backhaul_status_last.log ]; then
        cat /var/log/backhaul_status_last.log
    else
        echo "No cached status found! (service may not be installed yet)"
    fi
    echo
}
install_backhaul() {
    local SRV_TYPE="$1"
    sudo timedatectl set-timezone UTC

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

    echo "Downloading $FILE_NAME ..."
    if curl -L --fail --connect-timeout 10 --max-time 60 --speed-limit 10240 --speed-time 10 -o "$FILE_NAME" "$MY_GITHUB_URL/$FILE_NAME"; then
        echo "Download az github movafagh bood."
    else
        echo "Download az github failed (timeout ya error). Dar hale download az server iran..."
        if curl -L --fail --connect-timeout 10 --max-time 60 --speed-limit 10240 --speed-time 10 -o "$FILE_NAME" "$IRAN_URL/$FILE_NAME"; then
            echo "Download az server iran movafagh bood."
        else
            echo "ERROR: download az har do source failed!"
            exit 1
        fi
    fi

    mkdir -p /root/backhaul
    if tar -xzf "$FILE_NAME" -C /root/backhaul; then
        rm -f "$FILE_NAME"
        echo "Extract movafagh bood."
    else
        echo "Extract file failed!"
        exit 1
    fi

    echo "Kodam protocol ra mikhay?"
    select tunnel in "TCP (sade o sari')" "WSS Mux (zedd-filter & makhfi)"; do
      case $REPLY in
        1) TUNNEL_TYPE="tcp"; break ;;
        2) TUNNEL_TYPE="wssmux"; break ;;
        *) echo "Adad sahih vared kon lotfan!" ;;
      esac
    done

    read -p "Backhaul token: " BKTOKEN

    if [ "$SRV_TYPE" = "server" ]; then
        if [ "$TUNNEL_TYPE" = "tcp" ]; then
            read -p "Tunnel port (ex: 3080): " TUNNEL_PORT
            read -p "Tunneling ports (comma separated, e.g. 8880,8080,2086,80): " PORTS_RAW
            PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/","/g')
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
ports = [
\"$PORTS\"
]"
        else
            while true; do
                read -p "Tunnel port for WSS Mux (only 443 or 8443): " TUNNEL_PORT
                if [[ "$TUNNEL_PORT" == "443" || "$TUNNEL_PORT" == "8443" ]]; then
                    break
                else
                    echo "Faghat mituni 443 ya 8443 entekhab koni!"
                fi
            done
            read -p "Tunneling ports (comma separated, e.g. 8880,8080,2086,80): " PORTS_RAW
            PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/","/g')

            SSL_CERT="/root/server.crt"
            SSL_KEY="/root/server.key"
            
            BACKHAUL_CONFIG="[server]
bind_addr = \"0.0.0.0:$TUNNEL_PORT\"
transport = \"wssmux\"
token = \"$BKTOKEN\"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
mux_con = 8
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
tls_cert = \"$SSL_CERT\"
tls_key = \"$SSL_KEY\"
sniffer = true
web_port = 2060
sniffer_log = \"/root/backhaul.json\"
log_level = \"info\"
ports = [
\"$PORTS\"
]"
        fi
    else
        read -p "Iran server IP: " IRAN_IP
        read -p "Tunnel port (ex: 3080): " TUNNEL_PORT
        BACKHAUL_CONFIG="[client]
remote_addr = \"$IRAN_IP:$TUNNEL_PORT\"
transport = \"$TUNNEL_TYPE\"
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
    echo "Config created: /root/backhaul/config.toml"

    cat <<EOF | sudo tee /etc/systemd/system/backhaul.service > /dev/null
[Unit]
Description=Backhaul Reverse Tunnel Service
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

    sudo systemctl daemon-reload
    sudo systemctl enable backhaul.service
    sudo systemctl restart backhaul.service
}


install_monitoring() {
    echo "---------------------------------------------------"
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

    read -p "Enter tunnel host (e.g. 127.0.0.1): " TUNNEL_HOST
    read -p "Enter tunnel port (e.g. 3080): " TUNNEL_PORT

cat <<EOM > /root/backhaul_monitor.sh
#!/bin/bash
LOGFILE="/var/log/backhaul_monitor.log"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"
SERVICENAME="backhaul.service"
TIME=\$(date '+%Y-%m-%d %H:%M:%S')
RESTART_COUNT_FILE="/tmp/backhaul_restart_count"

check_tcp() {
  if nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT; then
    echo "\$TIME ✅ TCP port $TUNNEL_PORT on $TUNNEL_HOST is open" >> \$LOGFILE
    echo "0" > \$RESTART_COUNT_FILE
  else
    echo "\$TIME ❌ TCP port $TUNNEL_PORT on $TUNNEL_HOST is CLOSED." >> \$LOGFILE
    restart_service
  fi
}

check_ping() {
  ping -c 1 -W 1 $TUNNEL_HOST >/dev/null && echo "\$TIME 📶 Ping OK" >> \$LOGFILE || echo "\$TIME ⚠️ Ping failed" >> \$LOGFILE
}

check_http() {
  curl -s --connect-timeout 3 http://$TUNNEL_HOST:$TUNNEL_PORT >/dev/null && echo "\$TIME 🌐 HTTP OK" >> \$LOGFILE || echo "\$TIME 🚫 HTTP failed" >> \$LOGFILE
}

check_tls() {
  echo | openssl s_client -connect $TUNNEL_HOST:$TUNNEL_PORT -servername $TUNNEL_HOST -brief 2>/dev/null | grep -q 'Protocol' && echo "\$TIME 🔐 TLS OK" >> \$LOGFILE || echo "\$TIME ❌ TLS failed" >> \$LOGFILE
}

check_logs() {
  journalctl -u \$SERVICENAME --since "5 minutes ago" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > \$TMP_LOG
  if [ -s \$TMP_LOG ]; then
    echo "\$TIME ⚠️ Log issue detected" >> \$LOGFILE
    restart_service
  fi
  rm -f \$TMP_LOG
}

restart_service() {
  COUNT=\$(cat \$RESTART_COUNT_FILE 2>/dev/null || echo "0")
  COUNT=\$((COUNT+1))
  echo "\$TIME 🔄 Restarting \$SERVICENAME (attempt \$COUNT)..." >> \$LOGFILE
  systemctl restart \$SERVICENAME
  echo "\$COUNT" > \$RESTART_COUNT_FILE

  if [ \$COUNT -ge 3 ]; then
    echo "\$TIME 🔁 Max restart attempts reached. Rebooting server..." >> \$LOGFILE
    sleep 3
    reboot
  fi
}

check_tcp
check_ping
check_http
check_tls

CYCLE_COUNT_FILE="/tmp/cycle_count"
CYCLE_COUNT=\$(cat \$CYCLE_COUNT_FILE 2>/dev/null || echo "0")
CYCLE_COUNT=\$((CYCLE_COUNT+1))
if [ \$CYCLE_COUNT -ge 3 ]; then
  check_logs
  CYCLE_COUNT=0
fi
echo "\$CYCLE_COUNT" > \$CYCLE_COUNT_FILE

if [ -f "\$LOGFILE" ]; then
    tail -n 100 "\$LOGFILE" > "\$LOGFILE.tmp" && mv "\$LOGFILE.tmp" "\$LOGFILE"
fi
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

while true; do
    show_menu
    read -r opt
    case "$opt" in
        1)
            install_backhaul server
            install_monitoring
            echo -e "\n✅ Iran Server + Monitoring installed."
            ;;
        2)
            install_backhaul client
            install_monitoring
            echo -e "\n✅ Foreign Server + Monitoring installed."
            ;;
        3)
            install_monitoring
            echo -e "\n✅ Only Monitoring installed."
            ;;
        4)
            check_monitor_log
            ;;
        5)
            check_service_status
            ;;
        0)
            echo "Bye!"
            exit 0
            ;;
        *)
            echo "Option not recognized! Try again." ;;
    esac
done
