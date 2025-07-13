#!/bin/bash

LOG_FILE="/var/log/rathole_watchdog.log"
RESTART_COOLDOWN=300
LAST_RESTART=0
WARN_RESTART_COOLDOWN=300
REBOOT_CHECK_INTERVAL=43200  # 12 hours in seconds

while true; do
  TIME_NOW=$(date '+%Y-%m-%d %H:%M:%S')
  CURRENT_TIME=$(date +%s)

  # چک کردن اگر نیاز به ریبوت هست
  if [ -f /var/run/reboot-required ]; then
    echo "$TIME_NOW 🔁 System requires reboot. Rebooting now..." >> "$LOG_FILE"
    reboot
  fi

  # چک کردن سرویس rathole
  RATHOLE_SERVICE=$(systemctl list-units --type=service | grep -i rathole | grep -v watchdog | awk '{print $1}' | head -n1)

  if [ -n "$RATHOLE_SERVICE" ]; then
    ERROR_COUNT=$(journalctl -u "$RATHOLE_SERVICE" -n 5 --no-pager | grep -Ei '(error|failed|unavailable|disconnect)' | wc -l)
    WARN_COUNT=$(journalctl -u "$RATHOLE_SERVICE" -n 5 --no-pager | grep -Ei '(warn|warning)' | wc -l)

    # بررسی ارور
    if (( ERROR_COUNT >= 1 )); then
      if (( CURRENT_TIME - LAST_RESTART >= RESTART_COOLDOWN )); then
        echo "$TIME_NOW 🔁 Restarting $RATHOLE_SERVICE due to $ERROR_COUNT recent errors" >> "$LOG_FILE"
        systemctl restart "$RATHOLE_SERVICE"
        LAST_RESTART=$CURRENT_TIME
      else
        echo "$TIME_NOW ⏳ Cooldown active (waiting before next restart)" >> "$LOG_FILE"
      fi
    # بررسی WARN
    elif (( WARN_COUNT >= 1 )); then
      if (( CURRENT_TIME - LAST_RESTART >= WARN_RESTART_COOLDOWN )); then
        echo "$TIME_NOW ⚠️ Warning detected, restarting $RATHOLE_SERVICE after 5 minutes" >> "$LOG_FILE"
        systemctl restart "$RATHOLE_SERVICE"
        LAST_RESTART=$CURRENT_TIME
      else
        echo "$TIME_NOW ⏳ Cooldown active for WARN, waiting..." >> "$LOG_FILE"
      fi
    else
      echo "$TIME_NOW ✅ Rathole healthy (no errors or warnings in last 5 logs)" >> "$LOG_FILE"
    fi
  else
    echo "$TIME_NOW ⚠️ Rathole service not found." >> "$LOG_FILE"
  fi

  # محدود کردن حجم لاگ به ۵۰ خط
  if [ -f "$LOG_FILE" ]; then
    tail -n 50 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi

  sleep 90
done
EOW

chmod +x $WATCHDOG_SCRIPT

# ساخت فایل سرویس systemd
cat <<EOF | tee $SERVICE_FILE > /dev/null
[Unit]
Description=Rathole Log Watchdog
After=network.target

[Service]
ExecStart=/bin/bash $WATCHDOG_SCRIPT run
Restart=always
RestartSec=30
Type=simple

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی سرویس
systemctl daemon-reload
systemctl enable --now rathole_watchdog.service

echo "✅ Rathole Watchdog installed and running."
echo "📄 Logs: /var/log/rathole_watchdog.log"
