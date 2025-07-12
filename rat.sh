#!/bin/bash

echo "➡️ Installing Rathole Watchdog..."

# مسیر فایل اصلی
WATCHDOG_PATH="/root/rathole_watchdog.sh"
SERVICE_FILE="/etc/systemd/system/rathole_watchdog.service"
LOG_FILE="/var/log/rathole_watchdog.log"

# فایل watchdog.sh رو می‌سازه:
cat <<'EOW' > $WATCHDOG_PATH
#!/bin/bash

LOG_FILE="/var/log/rathole_watchdog.log"
RESTART_COOLDOWN=300
LAST_RESTART=0

while true; do
  TIME_NOW=$(date '+%Y-%m-%d %H:%M:%S')
  RATHOLE_SERVICE=$(systemctl list-units --type=service | grep -i rathole | grep -v watchdog | awk '{print $1}' | head -n1)

  if [ -n "$RATHOLE_SERVICE" ]; then
    ERROR_COUNT=$(journalctl -u "$RATHOLE_SERVICE" -n 5 --no-pager | grep -Ei '(error|failed|unavailable|disconnect)' | wc -l)

    if (( ERROR_COUNT >= 1 )); then
      CURRENT_TIME=$(date +%s)
      if (( CURRENT_TIME - LAST_RESTART >= RESTART_COOLDOWN )); then
        echo "$TIME_NOW Restarting $RATHOLE_SERVICE due to $ERROR_COUNT recent errors" >> "$LOG_FILE"
        systemctl restart "$RATHOLE_SERVICE"
        LAST_RESTART=$CURRENT_TIME
      else
        echo "$TIME_NOW Cooldown active, waiting..." >> "$LOG_FILE"
      fi
    else
      echo "$TIME_NOW Service healthy (no errors in last 5 logs)" >> "$LOG_FILE"
    fi
  else
    echo "$TIME_NOW Rathole service not found." >> "$LOG_FILE"
  fi

  sleep 90
done
EOW

chmod +x $WATCHDOG_PATH

# فایل سرویس systemd
cat <<EOF | tee $SERVICE_FILE > /dev/null
[Unit]
Description=Rathole Log Watchdog
After=network.target

[Service]
ExecStart=/bin/bash $WATCHDOG_PATH run
Restart=always
RestartSec=30
Type=simple

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و استارت
systemctl daemon-reload
systemctl enable --now rathole_watchdog.service

echo "✅ Watchdog installed, enabled and running."
echo "🔎 Logs: tail -f /var/log/rathole_watchdog.log"
