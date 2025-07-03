#!/bin/bash

set -e

# تنظیمات اولیه
clear
echo "====== BACKHAUL MASTER INSTALLER v1.2 ======"
echo "Select an option:"
echo "1) Setup Iran Server"
echo "2) Setup Foreign Server"
echo "3) Install Monitoring"
echo "4) View Monitoring Log"
echo "5) View Backhaul Status"
read -rp "Enter your choice (1-5): " opt

ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"
FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main/$FILE_NAME"
BACKUP_URL="http://37.32.13.161/$FILE_NAME"

# دانلود فایل باینری
download_binary() {
  echo "📦 Downloading $FILE_NAME..."
  if ! curl -fsSL --max-time 60 "$GITHUB_URL" -o "$FILE_NAME"; then
    echo "⚠️ GitHub failed, switching to backup..."
    curl -fsSL "$BACKUP_URL" -o "$FILE_NAME"
  fi
  mkdir -p /root/backhaul
  tar -xzf "$FILE_NAME" -C /root/backhaul || { echo "❌ Failed to extract."; exit 1; }
  rm -f "$FILE_NAME" /root/backhaul/LICENSE /root/backhaul/README.md
}

# تنظیم timezone به UTC
timedatectl set-timezone UTC

# مانیتورینگ
if [[ "$opt" == "3" ]]; then
  echo "🔍 Installing monitoring..."
  cat > /root/backhaul_monitor.sh <<EOF
#!/bin/bash

LOG_FILE="/var/log/backhaul_monitor.log"
MAX_LINES=100
STATUS=\$(systemctl is-active backhaul.service)

if ! journalctl -u backhaul.service | tail -n 20 | grep -q "listener started successfully"; then
  echo "\$(date '+%F %T') ❌ Control channel issue detected! Restarting..." >> "\$LOG_FILE"
  systemctl restart backhaul.service
elif [[ "\$STATUS" != "active" ]]; then
  echo "\$(date '+%F %T') ❌ backhaul.service is down! Restarting..." >> "\$LOG_FILE"
  systemctl restart backhaul.service
else
  echo "\$(date '+%F %T') ✅ backhaul.service is running." >> "\$LOG_FILE"
fi

# لاگ‌ها بیشتر از 100 خط نشه
tail -n \$MAX_LINES "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"

# چک ریبوت
if command -v needs-restarting >/dev/null && needs-restarting -r >/dev/null 2>&1; then
  echo "\$(date '+%F %T') 🔁 System needs reboot. Rebooting..." >> "\$LOG_FILE"
  reboot
fi
EOF

  chmod +x /root/backhaul_monitor.sh

  cat > /etc/systemd/system/backhaul-monitor.service <<EOF
[Unit]
Description=Backhaul Monitor

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
EOF

  cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Backhaul Monitor Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=backhaul-monitor.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now backhaul-monitor.timer
  echo "✅ Monitoring installed and running every 2 minutes."
  echo "Done – Thank you – Edited by PILOT CODE"
  exit 0
fi

# نمایش لاگ
if [[ "$opt" == "4" ]]; then
  echo "📄 Showing last 30 lines of monitoring log:"
  tail -n 30 /var/log/backhaul_monitor.log || echo "No log found."
  exit 0
fi

# نمایش وضعیت سرویس
if [[ "$opt" == "5" ]]; then
  echo "📊 backhaul.service status:"
  systemctl status backhaul.service --no-pager
  echo ""
  echo "🧠 Checking if system needs reboot:"
  if command -v needs-restarting >/dev/null && needs-restarting -r >/dev/null 2>&1; then
    echo "⚠️ Reboot recommended!"
  else
    echo "✅ No reboot needed."
  fi
  exit 0
fi

# نصب سرور ایران یا خارج
read -rp "Enter token: " TOKEN

if [[ "$opt" == "1" ]]; then
  read -rp "Enter tunnel bind port (e.g. 3080): " PORT
  read -rp "Enter tunnel ports list (comma-separated): " PORTS
  download_binary
  cat > /root/backhaul/config.toml <<EOF
[server]
bind_addr = "0.0.0.0:$PORT"
transport = "tcp"
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

elif [[ "$opt" == "2" ]]; then
  read -rp "Enter Iran server IP: " IP
  read -rp "Enter Iran server port: " PORT
  download_binary
  cat > /root/backhaul/config.toml <<EOF
[client]
remote_addr = "$IP:$PORT"
transport = "tcp"
token = "$TOKEN"
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
connection_pool = 8
aggressive_pool = false
sniffer = true
web_port = 2060
sniffer_log = "/root/backhaul.json"
log_level = "info"
EOF
else
  echo "❌ Invalid option."
  exit 1
fi

# سرویس بک‌هال
cat > /etc/systemd/system/backhaul.service <<EOF
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=/root/backhaul/backhaul -c /root/backhaul/config.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now backhaul.service

echo "✅ backhaul.service is up."
echo "Done – Thank you – Edited by PILOT CODE"
