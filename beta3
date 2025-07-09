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

install_monitoring() {
    echo "---------------------------------------------------"
    read -p "Har chand daghighe monitoring check beshe? (default: 2): " MON_MIN
    MON_MIN=${MON_MIN:-2}

    read -p "Enter tunnel host (e.g. 127.0.0.1): " TUNNEL_HOST
    read -p "Enter tunnel port (e.g. 3080): " TUNNEL_PORT

cat <<EOM > /root/backhaul_monitor.sh
#!/bin/bash
LOGFILE="/var/log/backhaul_monitor.log"
TMP_LOG="/tmp/backhaul_monitor_tmp.log"
SERVICENAME="backhaul.service"
TIME=\$(date '+%Y-%m-%d %H:%M:%S')
RESTART_COUNT_FILE="/tmp/backhaul_restart_count"

check_tcp() {
  if nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT; then
    echo "\$TIME ✅ TCP port $TUNNEL_PORT on $TUNNEL_HOST is open" >> \$LOGFILE
    echo "0" > \$RESTART_COUNT_FILE
  else
    echo "\$TIME ❌ TCP port $TUNNEL_PORT on $TUNNEL_HOST is CLOSED." >> \$LOGFILE
    restart_service
  fi
}

check_ping() {
  ping -c 1 -W 1 $TUNNEL_HOST >/dev/null && echo "\$TIME 📶 Ping OK" >> \$LOGFILE || echo "\$TIME ⚠️ Ping failed" >> \$LOGFILE
}

check_http() {
  curl -s --connect-timeout 3 http://$TUNNEL_HOST:$TUNNEL_PORT >/dev/null && echo "\$TIME 🌐 HTTP OK" >> \$LOGFILE || echo "\$TIME 🚫 HTTP failed" >> \$LOGFILE
}

check_tls() {
  echo | openssl s_client -connect $TUNNEL_HOST:$TUNNEL_PORT -servername $TUNNEL_HOST -brief 2>/dev/null | grep -q 'Protocol' && echo "\$TIME 🔐 TLS OK" >> \$LOGFILE || echo "\$TIME ❌ TLS failed" >> \$LOGFILE
}

check_logs() {
  journalctl -u \$SERVICENAME --since "5 minutes ago" | grep -E "(control channel has been closed|shutting down|channel dialer|inactive|dead)" > \$TMP_LOG
  if [ -s \$TMP_LOG ]; then
    echo "\$TIME ⚠️ Log issue detected" >> \$LOGFILE
    restart_service
  fi
  rm -f \$TMP_LOG
}

restart_service() {
  COUNT=\$(cat \$RESTART_COUNT_FILE 2>/dev/null || echo "0")
  COUNT=\$((COUNT+1))
  echo "\$TIME 🔄 Restarting \$SERVICENAME (attempt \$COUNT)..." >> \$LOGFILE
  systemctl restart \$SERVICENAME
  echo "\$COUNT" > \$RESTART_COUNT_FILE

  if [ \$COUNT -ge 3 ]; then
    echo "\$TIME 🔁 Max restart attempts reached. Rebooting server..." >> \$LOGFILE
    sleep 3
    reboot
  fi
}

check_tcp
check_ping
check_http
check_tls

CYCLE_COUNT_FILE="/tmp/cycle_count"
CYCLE_COUNT=\$(cat \$CYCLE_COUNT_FILE 2>/dev/null || echo "0")
CYCLE_COUNT=\$((CYCLE_COUNT+1))
if [ \$CYCLE_COUNT -ge 3 ]; then
  check_logs
  CYCLE_COUNT=0
fi
echo "\$CYCLE_COUNT" > \$CYCLE_COUNT_FILE

if [ -f "\$LOGFILE" ]; then
    tail -n 100 "\$LOGFILE" > "\$LOGFILE.tmp" && mv "\$LOGFILE.tmp" "\$LOGFILE"
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
