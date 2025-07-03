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

# تابع install_backhaul بدون تغییر در همینجا باقی می‌ماند...

install_monitoring() {
    echo "---------------------------------------------------"
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

cat <<'EOM' > /root/backhaul_monitor.sh
#!/bin/bash

LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"

CHECKTIME=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=$(systemctl is-active $SERVICENAME)
STATUS_DETAIL=$(systemctl status $SERVICENAME --no-pager | head -30)
LAST_CHECK=$(date --date='1 minute ago' '+%Y-%m-%d %H:%M')

journalctl -u $SERVICENAME --since "$LAST_CHECK:00" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > $TMP_LOG

# ✅ اضافه شده: اگر سیستم نیاز به ریبوت داشته باشد
if [ -f /var/run/reboot-required ]; then
  echo "$CHECKTIME 🔁 System requires reboot. Rebooting now..." >> $LOGFILE
  sleep 5
  reboot
fi

if [ "$STATUS" != "active" ]; then
  echo "$CHECKTIME ❌ $SERVICENAME is DOWN! [status: $STATUS]" >> $LOGFILE
  echo "$CHECKTIME ❗ Trying to restart $SERVICENAME..." >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo "$CHECKTIME 🔄 Restart command successful." >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo "$CHECKTIME 🟢 Status after restart: $NEW_STATUS" >> $LOGFILE
  else
    echo "$CHECKTIME 🚫 ERROR: Restart command FAILED!" >> $LOGFILE
  fi
elif [ -s $TMP_LOG ]; then
  echo "$CHECKTIME ⚠️ Issue detected in recent log:" >> $LOGFILE
  cat $TMP_LOG >> $LOGFILE
  echo "$CHECKTIME ❗ Trying to restart $SERVICENAME..." >> $LOGFILE
  if systemctl restart $SERVICENAME; then
    echo "$CHECKTIME 🔄 Restart command successful." >> $LOGFILE
    sleep 1
    NEW_STATUS=$(systemctl is-active $SERVICENAME)
    echo "$CHECKTIME 🟢 Status after restart: $NEW_STATUS" >> $LOGFILE
  else
    echo "$CHECKTIME 🚫 ERROR: Restart command FAILED!" >> $LOGFILE
  fi
else
  echo "$CHECKTIME ✅ Backhaul healthy. [status: $STATUS]" >> $LOGFILE
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
