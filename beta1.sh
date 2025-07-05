#!/bin/bash

set -e

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

MY_GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main"
IRAN_URL="http://37.32.13.161"

show_menu() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════╗"
    echo "║       BACKHAUL TOOL v1.2     ║"
    echo "╠══════════════════════════════╣"
    echo -e "║ ${YELLOW}1)${CYAN} Install Iran Server          ║"
    echo -e "║ ${YELLOW}2)${CYAN} Install Foreign Server       ║"
    echo -e "║ ${YELLOW}3)${CYAN} Install Only Monitoring      ║"
    echo -e "║ ${YELLOW}4)${CYAN} Check Monitoring Log         ║"
    echo -e "║ ${YELLOW}5)${CYAN} Check Service Status         ║"
    echo -e "║ ${YELLOW}6)${CYAN} ${RED}Uninstall Backhaul${CYAN}          ║"
    echo -e "║ ${YELLOW}0)${CYAN} Exit                        ║"
    echo "╚══════════════════════════════╝"
    echo -e "${NC}"
    echo -n "Select an option: "
}

uninstall_backhaul() {
    echo -e "\n${RED}⚠️ Uninstalling Backhaul...${NC}"
    
    # Stop and disable services
    if systemctl is-active --quiet backhaul.service; then
        systemctl stop backhaul.service
        systemctl disable backhaul.service
        echo -e "${YELLOW}→ Backhaul service stopped${NC}"
    fi
    
    if systemctl is-active --quiet backhaul-monitor.timer; then
        systemctl stop backhaul-monitor.timer
        systemctl disable backhaul-monitor.timer
        echo -e "${YELLOW}→ Monitoring timer stopped${NC}"
    fi
    
    # Remove systemd units
    rm -f /etc/systemd/system/backhaul.service
    rm -f /etc/systemd/system/backhaul-monitor.*
    systemctl daemon-reload
    
    # Remove files
    rm -rf /root/backhaul
    rm -f /root/backhaul_monitor.sh
    rm -f /var/log/backhaul_*.log
    rm -f /root/log.json
    rm -f /root/backhaul.json
    
    echo -e "\n${GREEN}✅ Backhaul completely uninstalled!${NC}"
}

check_monitor_log() {
    echo -e "\n${CYAN}---- Last 30 lines of monitoring log ----${NC}"
    if [ -f /var/log/backhaul_monitor.log ]; then
        tail -n 30 /var/log/backhaul_monitor.log
    else
        echo -e "${YELLOW}No monitor log found!${NC}"
    fi
}

check_service_status() {
    echo -e "\n${CYAN}---- Backhaul systemctl status ----${NC}"
    if [ -f /var/log/backhaul_status_last.log ]; then
        cat /var/log/backhaul_status_last.log
    else
        echo -e "${YELLOW}No cached status found!${NC}"
    fi
}

install_backhaul() {
    local SRV_TYPE="$1"
    sudo timedatectl set-timezone UTC

    # Detect OS and Architecture
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="386" ;;
        *) echo -e "${RED}Unsupported architecture!${NC}"; exit 1 ;;
    esac
    FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

    echo -e "\n${CYAN}==== Downloading Backhaul ====${NC}"
    if curl -L --fail --connect-timeout 10 --max-time 60 --speed-limit 10240 --speed-time 10 -o "$FILE_NAME" "$MY_GITHUB_URL/$FILE_NAME"; then
        echo -e "${GREEN}✓ Downloaded from GitHub${NC}"
    else
        echo -e "${YELLOW}GitHub download failed, trying Iran server...${NC}"
        if curl -L --fail --connect-timeout 10 --max-time 60 --speed-limit 10240 --speed-time 10 -o "$FILE_NAME" "$IRAN_URL/$FILE_NAME"; then
            echo -e "${GREEN}✓ Downloaded from Iran server${NC}"
        else
            echo -e "${RED}ERROR: Download failed from all sources!${NC}"
            exit 1
        fi
    fi

    mkdir -p /root/backhaul
    if tar -xzf "$FILE_NAME" -C /root/backhaul; then
        rm -f "$FILE_NAME"
        echo -e "${GREEN}✓ Extraction successful${NC}"
    else
        echo -e "${RED}Extraction failed!${NC}"
        exit 1
    fi

    echo -e "\n${CYAN}==== Configuration ====${NC}"
    echo -e "${YELLOW}Select protocol:${NC}"
    select tunnel in "TCP (simple)" "WSS Mux (secure)"; do
        case $REPLY in
            1) TUNNEL_TYPE="tcp"; break ;;
            2) TUNNEL_TYPE="wssmux"; break ;;
            *) echo -e "${RED}Invalid choice!${NC}" ;;
        esac
    done

    read -p "Backhaul token: " BKTOKEN

    if [ "$SRV_TYPE" = "server" ]; then
        if [ "$TUNNEL_TYPE" = "tcp" ]; then
            read -p "Tunnel port (default: 9091): " TUNNEL_PORT
            TUNNEL_PORT=${TUNNEL_PORT:-9091}
            read -p "MTU (default: 1500): " MTU
            MTU=${MTU:-1500}
            read -p "Tunneling ports (comma separated, e.g. 8080,2086): " PORTS_RAW
            PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/","/g')

            BACKHAUL_CONFIG="[server]
bind_addr = \":$TUNNEL_PORT\"
transport = \"tcp\"
accept_udp = false
token = \"$BKTOKEN\"
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
sniffer_log = \"/root/log.json\"
log_level = \"info\"
proxy_protocol= false
tun_name = \"backhaul\"
tun_subnet = \"10.10.10.0/24\"
mtu = $MTU
ports = [
\"$PORTS\"
]"
        else
            # WSS Mux config for server
            while true; do
                read -p "Tunnel port for WSS Mux (only 443 or 8443): " TUNNEL_PORT
                if [[ "$TUNNEL_PORT" == "443" || "$TUNNEL_PORT" == "8443" ]]; then
                    break
                else
                    echo -e "${RED}Only 443 or 8443 are allowed!${NC}"
                fi
            done
            read -p "Tunneling ports (comma separated, e.g. 8880,8080,2086,80): " PORTS_RAW
            PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/","/g')
            read -p "Do you already have SSL cert & key? (y/n): " SSL_HAS
            if [[ "$SSL_HAS" =~ ^[Yy]$ ]]; then
                read -p "Enter path to SSL certificate file (ex: /root/server.crt): " SSL_CERT
                read -p "Enter path to SSL key file (ex: /root/server.key): " SSL_KEY
                echo -e "${YELLOW}SSL cert: $SSL_CERT"
                echo "SSL key: $SSL_KEY${NC}"
            else
                echo -e "${YELLOW}Installing openssl and generating SSL certificate...${NC}"
                sudo apt-get update && sudo apt-get install -y openssl
                openssl genpkey -algorithm RSA -out /root/server.key -pkeyopt rsa_keygen_bits:2048
                openssl req -new -key /root/server.key -out /root/server.csr
                openssl x509 -req -in /root/server.csr -signkey /root/server.key -out /root/server.crt -days 365
                SSL_CERT="/root/server.crt"
                SSL_KEY="/root/server.key"
                echo -e "${GREEN}SSL cert and key created: $SSL_CERT & $SSL_KEY${NC}"
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
            read -p "Tunnel port (default: 9091): " TUNNEL_PORT
            TUNNEL_PORT=${TUNNEL_PORT:-9091}
            read -p "MTU (default: 1500): " MTU
            MTU=${MTU:-1500}

            BACKHAUL_CONFIG="[client]
remote_addr = \"$IRAN_IP:$TUNNEL_PORT\"
transport = \"tcp\"
token = \"$BKTOKEN\"
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
sniffer_log = \"/root/log.json\"
log_level = \"info\"
ip_limit= false
tun_name = \"backhaul\"
tun_subnet = \"10.10.10.0/24\"
mtu = $MTU"
        else
            # WSS Mux config for client
            read -p "Iran server IP: " IRAN_IP
            while true; do
                read -p "Tunnel port for WSS Mux (only 443 or 8443): " TUNNEL_PORT
                if [[ "$TUNNEL_PORT" == "443" || "$TUNNEL_PORT" == "8443" ]]; then
                    break
                else
                    echo -e "${RED}Only 443 or 8443 are allowed!${NC}"
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
    echo -e "${GREEN}✓ Config created: /root/backhaul/config.toml${NC}"

    # Create systemd service
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
    echo -e "${GREEN}✓ Backhaul service started${NC}"
}

install_monitoring() {
    echo -e "\n${CYAN}==== Monitoring Setup ====${NC}"
    read -p "Check interval (minutes, default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

    cat <<'EOM' > /root/backhaul_monitor.sh
#!/bin/bash

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"

CHECKTIME=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=$(systemctl is-active $SERVICENAME)
STATUS_DETAIL=$(systemctl status $SERVICENAME --no-pager | head -30)
LAST_CHECK=$(date --date='1 minute ago' '+%Y-%m-%d %H:%M')

if [ -f /var/run/reboot-required ]; then
  echo -e "$CHECKTIME ${YELLOW}🔁 System requires reboot. Rebooting now...${NC}" >> $LOGFILE
  sleep 5
  reboot
fi

journalctl -u $SERVICENAME --since "$LAST_CHECK:00" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > $TMP_LOG

if [ "$STATUS" != "active" ]; then
  echo -e "$CHECKTIME ${RED}❌ $SERVICENAME is DOWN! [status: $STATUS]${NC}" >> $LOGFILE
  echo -e "$CHECKTIME ${YELLOW}❗ Trying to restart $SERVICENAME...${NC}" >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo -e "$CHECKTIME ${GREEN}🔄 Restart command successful.${NC}" >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo -e "$CHECKTIME ${GREEN}🟢 Status after restart: $NEW_STATUS${NC}" >> $LOGFILE
  else
    echo -e "$CHECKTIME ${RED}🚫 ERROR: Restart command FAILED!${NC}" >> $LOGFILE
  fi
elif [ -s $TMP_LOG ]; then
  echo -e "$CHECKTIME ${YELLOW}⚠️ Issue detected in recent log:${NC}" >> $LOGFILE
  cat $TMP_LOG >> $LOGFILE
  echo -e "$CHECKTIME ${YELLOW}❗ Trying to restart $SERVICENAME...${NC}" >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo -e "$CHECKTIME ${GREEN}🔄 Restart command successful.${NC}" >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo -e "$CHECKTIME ${GREEN}🟢 Status after restart: $NEW_STATUS${NC}" >> $LOGFILE
  else
    echo -e "$CHECKTIME ${RED}🚫 ERROR: Restart command FAILED!${NC}" >> $LOGFILE
  fi
else
  echo -e "$CHECKTIME ${GREEN}✅ Backhaul healthy. [status: $STATUS]${NC}" >> $LOGFILE
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

    # Create monitoring service
    cat <<EOF | sudo tee /etc/systemd/system/backhaul-monitor.service > /dev/null
[Unit]
Description=Backhaul Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
User=root
EOF

    # Create monitoring timer
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
    sudo journalctl --rotate
    sudo journalctl --vacuum-time=1s
    echo "" > /var/log/backhaul_monitor.log
    echo -e "${GREEN}✓ Monitoring installed (checks every $MON_MIN minutes)${NC}"
}

# Main loop
while true; do
    show_menu
    read -r opt
    case "$opt" in
        1)
            install_backhaul server
            install_monitoring
            echo -e "\n${GREEN}✅ Iran Server + Monitoring installed successfully!${NC}"
            ;;
        2)
            install_backhaul client
            install_monitoring
            echo -e "\n${GREEN}✅ Foreign Server + Monitoring installed successfully!${NC}"
            ;;
        3)
            install_monitoring
            echo -e "\n${GREEN}✓ Monitoring installed successfully!${NC}"
            ;;
        4)
            check_monitor_log
            ;;
        5)
            check_service_status
            ;;
        6)
            uninstall_backhaul
            ;;
        0)
            echo -e "\n${CYAN}Goodbye! 👋${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option!${NC}"
            ;;
    esac
    read -p "Press Enter to continue..."
done
