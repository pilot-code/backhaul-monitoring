#!/bin/bash

set -e

clear
echo "========================="
echo "  BACKHAUL INSTALLATION  "
echo "========================="

echo ""
echo "Choose installation mode:"
echo "1) Iran Server"
echo "2) Foreign Server"
echo "3) Monitoring Only"
read -rp "Select (1-3): " MODE

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

DOWNLOAD_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main/$FILE_NAME"
BACKUP_URL="http://37.32.13.161/$FILE_NAME"

# Get token
read -rp "Enter your token: " TOKEN

# Download binary with fallback
echo "Downloading $FILE_NAME ..."
if ! curl -fsSL --max-time 60 "$DOWNLOAD_URL" -o "$FILE_NAME"; then
  echo "⚠️ GitHub download failed, switching to backup server..."
  curl -fsSL "$BACKUP_URL" -o "$FILE_NAME"
fi

mkdir -p /root/backhaul
if tar -xzf "$FILE_NAME" -C /root/backhaul; then
  rm -f "$FILE_NAME" /root/backhaul/LICENSE /root/backhaul/README.md
  echo "✅ Backhaul extracted."
else
  echo "❌ Extraction failed!"
  exit 1
fi

# Set timezone
sudo timedatectl set-timezone UTC

# ========================
# Iran Server Setup
# ========================
if [[ "$MODE" == "1" ]]; then
  read -rp "Enter tunnel bind port (e.g., 3080): " PORT
  read -rp "Enter tunnel ports list (comma-separated): " PORTS

  cat > /root/backhaul/config.toml <<EOF
[server]
bind_addr = "0.0.0.0:$PORT"
transport = "tcp"
accept_udp = false
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

# ========================
# Foreign Server Setup
# ========================
elif [[ "$MODE" == "2" ]]; then
  read -rp "Enter Iran server IP: " IP
  read -rp "Enter Iran server port (e.g., 3080): " PORT

  cat > /root/backhaul/config.toml <<EOF
[client]
remote_addr = "$IP:$PORT"
transport = "tcp"
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

# ========================
# Monitoring Setup
# ========================
elif [[ "$MODE" == "3" ]]; then
  read -rp "Monitoring interval (minutes, default 2): " MIN
  MIN=${MIN:-2}
  cat > /root/backhaul_monitor.sh <<EOF
#!/bin/bash

LOG_FILE="/var/log/backhaul_monitor.log"
STATUS=\$(systemctl is-active backhaul.service)

if [[ "\$STATUS" != "active" ]]; then
  echo "\$(date '+%Y-%m-%d %H:%M:%S') ❌ backhaul.service is down! Restarting..." >> "\$LOG_FILE"
  systemctl restart backhaul.service
else
  echo "\$(date '+%Y-%m-%d %H:%M:%S') ✅ backhaul.service is running." >> "\$LOG_FILE"
fi

tail -n 100 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"
EOF

  chmod +x /root/backhaul_monitor.sh

  cat > /etc/systemd/system/backhaul-monitor.service <<EOF
[Unit]
Description=Backhaul Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
EOF

  cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Run Backhaul Monitor every $MIN minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=${MIN}min
Unit=backhaul-monitor.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now backhaul-monitor.timer
  echo "✅ Monitoring activated every $MIN minutes."
  exit 0
fi

# ========================
# Common: Create Systemd
# ========================
cat > /etc/systemd/system/backhaul.service <<EOF
[Unit]
Description=Backhaul Reverse Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/root/backhaul/backhaul -c /root/backhaul/config.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now backhaul.service

echo -e "\n=============================="
echo -e "✅ Installation Completed"
echo -e "EDITED BY PILOT CODE"
echo -e "=============================="
