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
            read -p "Do you already have SSL cert & key? (y/n): " SSL_HAS
            if [[ "$SSL_HAS" =~ ^[Yy]$ ]]; then
                read -p "Enter path to SSL certificate file (ex: /root/server.crt): " SSL_CERT
                read -p "Enter path to SSL key file (ex: /root/server.key): " SSL_KEY
                echo "SSL cert: $SSL_CERT"
                echo "SSL key: $SSL_KEY"
            else
                echo "Installing openssl and generating SSL certificate..."
                sudo apt-get update && sudo apt-get install -y openssl
                openssl genpkey -algorithm RSA -out /root/server.key -pkeyopt rsa_keygen_bits:2048
                openssl req -new -key /root/server.key -out /root/server.csr
                openssl x509 -req -in /root/server.csr -signkey /root/server.key -out /root/server.crt -days 365
                SSL_CERT="/root/server.crt"
                SSL_KEY="/root/server.key"
                echo "SSL cert and key sakhte shod: $SSL_CERT & $SSL_KEY"
            fi
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
        if [ "$TUNNEL_TYPE" = "tcp" ]; then
            read -p "Iran server IP: " IRAN_IP
            read -p "Tunnel port (ex: 3080): " TUNNEL_PORT
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
        else
            read -p "Iran server IP: " IRAN_IP
            while true; do
                read -p "Tunnel port for WSS Mux (only 443 or 8443): " TUNNEL_PORT
                if [[ "$TUNNEL_PORT" == "443" || "$TUNNEL_PORT" == "8443" ]]; then
                    break
                else
                    echo "Faghat mituni 443 ya 8443 entekhab koni!"
                fi
            done
            BACKHAUL_CONFIG="[client]
remote_addr = \"$IRAN_IP:$TUNNEL_PORT\"
edge_ip = \"\"
transport = \"wssmux\"
token = \"$BKTOKEN\"
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
connection_pool = 8
aggressive_pool = false
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
sniffer = true
web_port = 2060
sniffer_log = \"/root/backhaul.json\"
log_level = \"info\""
        fi
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
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

    echo "Aya in server Iran ast ya Kharej?"
    echo "1) Iran"
    echo "2) Kharej"
    read -p "Entekhab kon (1 ya 2): " choice

    if [ "$choice" = "1" ]; then
      TUNNEL_HOST="127.0.0.1"
      read -p "Port tunnel: " TUNNEL_PORT
    elif [ "$choice" = "2" ]; then
      read -p "IP server Iran: " TUNNEL_HOST
      read -p "Port tunnel: " TUNNEL_PORT
    else
      echo "Adad sahih vared konid!"
      exit 1
    fi

cat <<EOM > /root/backhaul_monitor.sh
#!/bin/bash

LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"
CHECKTIME=\$(date '+%Y-%m-%d %H:%M:%S')
TUNNEL_HOST="$TUNNEL_HOST"
TUNNEL_PORT="$TUNNEL_PORT"
LAST_CHECK=\$(date --date='1 minute ago' '+%Y-%m-%d %H:%M')

STATUS=\$(systemctl is-active \$SERVICENAME)
STATUS_DETAIL=\$(systemctl status \$SERVICENAME --no-pager | head -30)

# Check if system requires reboot
if [ -f /var/run/reboot-required ]; then
  echo "\$CHECKTIME 🔁 /var/run/reboot-required found. Rebooting now..." >> \$LOGFILE
  sleep 5
  reboot
fi

PING_OK=false
if ping -c1 -W1 \$TUNNEL_HOST >/dev/null; then
  PING_OK=true
fi

journalctl -u \$SERVICENAME --since "\$LAST_CHECK:00" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > \$TMP_LOG

if [ "\$STATUS" != "active" ]; then
  echo "\$CHECKTIME ❌ \$SERVICENAME is DOWN! Restarting..." >> \$LOGFILE
  systemctl restart \$SERVICENAME
elif [ "\$PING_OK" = true ]; then
  if [ -s \$TMP_LOG ]; then
    echo "\$CHECKTIME ⚠️ Log error detected after successful ping" >> \$LOGFILE
    cat \$TMP_LOG >> \$LOGFILE
    echo "\$CHECKTIME ❗ Restarting due to log issue..." >> \$LOGFILE
    systemctl restart \$SERVICENAME
  else
    echo "\$CHECKTIME ✅ Ping OK, log clean, service healthy" >> \$LOGFILE
  fi
else
  echo "\$CHECKTIME ❌ Ping failed to \$TUNNEL_HOST. Restarting \$SERVICENAME..." >> \$LOGFILE
  systemctl restart \$SERVICENAME
fi

echo "---- [ \$CHECKTIME : systemctl status \$SERVICENAME ] ----" > /var/log/backhaul_status_last.log
echo "\$STATUS_DETAIL" >> /var/log/backhaul_status_last.log

rm -f \$TMP_LOG

if [ -f "\$LOGFILE" ]; then
  tail -n 50 "\$LOGFILE" > "\$LOGFILE.tmp" && mv "\$LOGFILE.tmp" "\$LOGFILE"
fi
tail -n 35 /var/log/backhaul_status_last.log > /var/log/backhaul_status_last.log.tmp && mv /var/log/backhaul_status_last.log.tmp /var/log/backhaul_status_last.log
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
echo "✅ Monitoring configured for \$TUNNEL_HOST:\$TUNNEL_PORT every \$MON_MIN minutes."
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
