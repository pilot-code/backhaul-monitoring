#!/bin/bash

sudo timedatectl set-timezone UTC

MY_GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main"
IRAN_URL="http://37.32.13.161"

echo "Install mode ra entekhab kon:"
select mode in "Iran server (backhaul + monitoring)" "Kharej server (backhaul + monitoring)" "Only monitoring"; do
    case $REPLY in
        1) SRV_TYPE="server"; break;;
        2) SRV_TYPE="client"; break;;
        3) SRV_TYPE="monitor"; break;;
        *) echo "Lotfan adad sahih vared kon!";;
    esac
done

if [ "$SRV_TYPE" != "monitor" ]; then
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
fi

echo "---------------------------------------------------"
read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
MON_MIN=${MON_MIN:-2}

cat <<'EOM' > /root/backhaul_monitor.sh
#!/bin/bash

LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"

STATUS=$(systemctl is-active $SERVICENAME)
if [ "$STATUS" = "inactive" ] || [ "$STATUS" = "failed" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ $SERVICENAME is down! Restarting..." >> $LOGFILE
  systemctl restart $SERVICENAME
  exit 0
fi

# Vaghti manitoring har 2 daqiqe ejra mishe, log haye 2 daqiqe ghabl ra check kon
LAST_CHECK=$(date --date='2 minute ago' '+%Y-%m-%d %H:%M')
journalctl -u $SERVICENAME --since "$LAST_CHECK:00" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > /tmp/backhaul_monitor_tmp.log

if [ -s /tmp/backhaul_monitor_tmp.log ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ Issue detected in log (recent):" >> $LOGFILE
  cat /tmp/backhaul_monitor_tmp.log >> $LOGFILE
  echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ Restarting $SERVICENAME ..." >> $LOGFILE
  systemctl restart $SERVICENAME
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Backhaul healthy." >> $LOGFILE
fi

rm -f /tmp/backhaul_monitor_tmp.log

# فقط 100 خط آخر را نگه دار، بقیه را پاک کن (auto-truncate)
if [ -f "$LOGFILE" ]; then
    tail -n 100 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
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

# ----------- SECTION: REMOVE ALL CRONJOBS (ROOT & UBUNTU) -----------
crontab -r || true
crontab -r -u ubuntu || true

# ----------- SECTION: REBOOT CHECKER (EVERY 12 HOURS) -----------
cat <<'EOF' > /root/reboot-checker.sh
#!/bin/bash
crontab -r || true
crontab -r -u ubuntu || true

if [ -f /var/run/reboot-required ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') 🚨 System restart required! Rebooting now..." >> /var/log/reboot-checker.log
    sleep 2
    reboot
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ No reboot needed." >> /var/log/reboot-checker.log
fi
EOF

chmod +x /root/reboot-checker.sh

cat <<EOF | sudo tee /etc/systemd/system/reboot-checker.service > /dev/null
[Unit]
Description=Check if reboot required and reboot if needed

[Service]
Type=oneshot
ExecStart=/root/reboot-checker.sh
User=root
EOF

cat <<EOF | sudo tee /etc/systemd/system/reboot-checker.timer > /dev/null
[Unit]
Description=Check for reboot requirement every 12 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now reboot-checker.timer
sudo systemctl restart reboot-checker.timer

echo "Setup completed. Monitoring and reboot-check will run. All cronjobs removed."
tail -n 3 /var/log/backhaul_monitor.log
tail -n 3 /var/log/reboot-checker.log

echo -e "\nDone\nThank you\nEdited by amirreza pilotcode"
