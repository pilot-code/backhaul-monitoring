#!/bin/bash

CONFIG_PATH="/root/rathole_watchdog.conf"
SERVICE_FILE="/etc/systemd/system/rathole_watchdog.service"
LOG_FILE="/var/log/rathole_watchdog.log"
MODE="$1"

if [ "$MODE" != "run" ]; then
  clear
  echo "==== Rathole Watchdog Control ===="
  echo "1) Install and enable watchdog"
  echo "2) Restart watchdog"
  echo "3) Delete watchdog"
  echo "0) Exit"
  read -p "Select option: " choice

  case "$choice" in
    1)
      cat <<EOF | tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Rathole Log Watchdog
After=network.target

[Service]
ExecStart=/bin/bash /root/rathole_watchdog.sh run
Restart=always
RestartSec=30
Type=simple

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      systemctl enable --now rathole_watchdog.service
      echo "Watchdog installed and running."
      ;;
    2)
      systemctl restart rathole_watchdog.service
      echo "Watchdog restarted." >> "$LOG_FILE"
      ;;
    3)
      systemctl stop rathole_watchdog.service
      systemctl disable rathole_watchdog.service
      rm -f "$SERVICE_FILE"
      systemctl daemon-reload
      echo "Watchdog removed." >> "$LOG_FILE"
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Invalid option"
      exit 1
      ;;
  esac
  exit 0
fi

# Mode run - Watchdog logic
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
        echo "$TIME_NOW Cooldown active." >> "$LOG_FILE"
      fi
    else
      echo "$TIME_NOW No critical errors detected in last 5 logs." >> "$LOG_FILE"
    fi
  else
    echo "$TIME_NOW Rathole service not found." >> "$LOG_FILE"
  fi

  sleep 90
done
