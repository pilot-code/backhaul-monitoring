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
TIME=\$(date '+%Y-%m-%d %H:%M:%S')

check_tcp() {
  if nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT; then
    echo "\$TIME ✅ TCP port $TUNNEL_PORT on $TUNNEL_HOST is open" >> \$LOGFILE
  else
    echo "\$TIME ❌ TCP port $TUNNEL_PORT on $TUNNEL_HOST is CLOSED. Restarting..." >> \$LOGFILE
    systemctl restart backhaul.service
  fi
}

check_ping() {
  if ping -c 1 -W 1 $TUNNEL_HOST > /dev/null; then
    echo "\$TIME 📶 Ping to $TUNNEL_HOST successful" >> \$LOGFILE
  else
    echo "\$TIME ⚠️ Ping to $TUNNEL_HOST failed" >> \$LOGFILE
  fi
}

check_http() {
  if curl -s --connect-timeout 3 http://$TUNNEL_HOST:$TUNNEL_PORT > /dev/null; then
    echo "\$TIME 🌐 HTTP response from $TUNNEL_HOST:$TUNNEL_PORT OK" >> \$LOGFILE
  else
    echo "\$TIME 🚫 No HTTP response from $TUNNEL_HOST:$TUNNEL_PORT" >> \$LOGFILE
  fi
}

check_tls() {
  if echo | openssl s_client -connect $TUNNEL_HOST:$TUNNEL_PORT -servername $TUNNEL_HOST -brief 2>/dev/null | grep -q 'Protocol'; then
    echo "\$TIME 🔐 TLS handshake successful with $TUNNEL_HOST:$TUNNEL_PORT" >> \$LOGFILE
  else
    echo "\$TIME ❌ TLS handshake FAILED with $TUNNEL_HOST:$TUNNEL_PORT" >> \$LOGFILE
  fi
}

check_tcp
check_ping
check_http
check_tls

# Keep log limited
if [ -f "\$LOGFILE" ]; then
    tail -n 100 "\$LOGFILE" > "\$LOGFILE.tmp" && mv "\$LOGFILE.tmp" "\$LOGFILE"
fi
EOM

    chmod +x /root/backhaul_monitor.sh

cat <<EOF | sudo tee /etc/systemd/system/backhaul-monitor.service > /dev/null
[Unit]
Description=Backhaul Tunnel Health Check

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
User=root
EOF

cat <<EOF | sudo tee /etc/systemd/system/backhaul-monitor.timer > /dev/null
[Unit]
Description=Run Backhaul Tunnel Health Check every $MON_MIN minutes

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
