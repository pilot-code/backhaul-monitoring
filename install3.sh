#!/bin/bash

set -e

# Set timezone to UTC
sudo timedatectl set-timezone UTC

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Menu
clear
echo -e "${YELLOW}Welcome to Backhaul Setup Script${NC}"
echo "Select mode:"
echo "1. Install on Iran Server"
echo "2. Install on Foreign Server"
echo "3. Install Monitoring System"
echo "4. Update Monitoring System"
read -p "Enter your choice [1-4]: " MODE

if [[ "$MODE" == "1" ]]; then
    read -p "Enter tunnel port (e.g., 3080): " TUNNEL_PORT
    read -p "Enter token: " TOKEN
    read -p "Enter ports for tunneling (comma separated): " PORTS
    read -p "Protocol? (tcp/wssmux): " PROTO

    mkdir -p /root/backhaul

    # WSSMUX requires SSL
    if [[ "$PROTO" == "wssmux" ]]; then
        read -p "Do you already have SSL cert and key in /root? (y/n): " HAS_SSL
        if [[ "$HAS_SSL" != "y" ]]; then
            sudo apt-get update
            sudo apt-get install -y openssl
            openssl genpkey -algorithm RSA -out /root/server.key -pkeyopt rsa_keygen_bits:2048
            openssl req -new -key /root/server.key -out /root/server.csr
            openssl x509 -req -in /root/server.csr -signkey /root/server.key -out /root/server.crt -days 365
        fi
    fi

    # Create config.toml
    cat > /root/backhaul/config.toml <<EOF
[server]
bind_addr = "0.0.0.0:$TUNNEL_PORT"
transport = "$PROTO"
token = "$TOKEN"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = 2060
sniffer_log = "/root/backhaul.json"
log_level = "info"
ports = [${PORTS//,/","}]
EOF

    if [[ "$PROTO" == "wssmux" ]]; then
    cat >> /root/backhaul/config.toml <<EOF
mux_con = 8
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
tls_cert = "/root/server.crt"
tls_key = "/root/server.key"
EOF
    fi

elif [[ "$MODE" == "2" ]]; then
    read -p "Enter Iran server IP: " SERVER_IP
    read -p "Enter tunnel port: " TUNNEL_PORT
    read -p "Enter token: " TOKEN
    read -p "Protocol? (tcp/wssmux): " PROTO

    mkdir -p /root/backhaul

    cat > /root/backhaul/config.toml <<EOF
[client]
remote_addr = "$SERVER_IP:$TUNNEL_PORT"
transport = "$PROTO"
token = "$TOKEN"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = 2060
sniffer_log = "/root/backhaul.json"
log_level = "info"
EOF

    if [[ "$PROTO" == "wssmux" ]]; then
    cat >> /root/backhaul/config.toml <<EOF
mux_version = 1
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 65536
EOF
    fi
fi

if [[ "$MODE" == "1" || "$MODE" == "2" ]]; then
    # Download binary with fallback
    ARCH=$(uname -m); OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
    FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

    echo -e "\n${YELLOW}Downloading $FILE_NAME...${NC}"
    timeout 60 curl -fLo "$FILE_NAME" "https://github.com/pilot-code/backhaul-monitoring/raw/main/$FILE_NAME" || \
    curl -fLo "$FILE_NAME" "http://37.32.13.161/$FILE_NAME"

    tar -xzf "$FILE_NAME" -C /root/backhaul || { echo -e "${RED}Extraction failed!${NC}"; exit 1; }
    rm -f "$FILE_NAME" /root/backhaul/LICENSE /root/backhaul/README.md

    # Create service
    cat > /etc/systemd/system/backhaul.service <<EOF
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

    systemctl daemon-reload
    systemctl enable --now backhaul.service

    echo -e "${GREEN}Backhaul setup complete.${NC}"
fi

if [[ "$MODE" == "3" || "$MODE" == "4" ]]; then
    # Install monitor script
    cat > /root/backhaul_monitor.sh <<'EOL'
#!/bin/bash
LOG_FILE="/var/log/backhaul_monitor.log"
MAX_LINES=100

# Check reboot needed
if [ -f /var/run/reboot-required ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ⚠️ Reboot required. Rebooting now..." >> $LOG_FILE
  reboot
fi

# Check backhaul
if ! systemctl is-active --quiet backhaul.service; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ backhaul.service is down! Restarting..." >> $LOG_FILE
  systemctl restart backhaul.service
else
  if journalctl -u backhaul.service --since "5 minutes ago" | grep -qE 'control channel has been closed|connect: connection refused'; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ Control channel issue detected! Restarting..." >> $LOG_FILE
    systemctl restart backhaul.service
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') ✅ Backhaul healthy." >> $LOG_FILE
  fi
fi

# Trim log
tail -n $MAX_LINES $LOG_FILE > ${LOG_FILE}.tmp && mv ${LOG_FILE}.tmp $LOG_FILE
EOL

    chmod +x /root/backhaul_monitor.sh
    echo -e "${GREEN}Monitor script installed.${NC}"

    # Create service
    cat > /etc/systemd/system/backhaul-monitor.service <<EOF
[Unit]
Description=Backhaul Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
EOF

    # Create timer (every 12h, start immediately)
    cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Backhaul Health Check Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now backhaul-monitor.timer
    echo -e "${GREEN}Monitoring system active (every 12h).${NC}"

    # Add log viewer
    echo -e "\nTo check logs: ${YELLOW}tail -f /var/log/backhaul_monitor.log${NC}"
fi

echo -e "\n${GREEN}Done! Thank you\nEdited by amirreza safari ✅${NC}"
