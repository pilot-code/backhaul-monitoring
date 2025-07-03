#!/bin/bash

# ============ COLOR SETUP ============
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
BOLD="$(tput bold)"
RESET="$(tput sgr0)"

# ============ LOG FILES ============
LOG_FILE="/var/log/backhaul_monitor.log"
EXEC_LOG="/var/log/backhaul_exec.log"

# ============ TIMEZONE SETUP ============
echo "${BLUE}Setting server timezone to UTC...${RESET}"
sudo timedatectl set-timezone UTC

# ============ FUNCTION: CHECK & REBOOT IF NEEDED ============
check_reboot_required() {
    if [ -f /var/run/reboot-required ]; then
        echo "${YELLOW}Reboot required. Rebooting now...${RESET}" | tee -a "$LOG_FILE"
        reboot
    fi
}

# ============ FUNCTION: CLEAR OLD CRON JOBS ============
clear_old_cron() {
    crontab -l 2>/dev/null | grep -v backhaul_monitor.sh | crontab -
}

# ============ FUNCTION: CREATE MONITOR SCRIPT ============
create_monitor_script() {
    cat > /root/backhaul_monitor.sh <<EOF
#!/bin/bash

MAX_LOGS=100
LOG_FILE="$LOG_FILE"
EXEC_LOG="$EXEC_LOG"
TELEGRAM_API="\$1"

log() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" | tee -a "\$LOG_FILE"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" >> "\$EXEC_LOG"
    if [[ ! -z "\$TELEGRAM_API" && "\$1" == "❌"* ]]; then
        curl -s -X POST "\$TELEGRAM_API" -d "text=\$1"
    fi
    tail -n \$MAX_LOGS "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"
}

check_backhaul() {
    STATUS=\$(systemctl is-active backhaul.service)
    if [[ "\$STATUS" != "active" ]]; then
        log "❌ backhaul.service is down! Restarting..."
        systemctl restart backhaul.service
        return
    fi

    ERROR_FOUND=
    if journalctl -u backhaul.service -n 30 | grep -qiE 'error|refused|channel closed|control channel'; then
        log "❌ Control channel issue detected! Restarting..."
        systemctl restart backhaul.service
        return
    fi

    CPU=\$(top -bn1 | grep '%Cpu' | awk '{print 2}')
    MEM=\$(free -m | awk '/Mem/ {printf("%.2f", \$3/\$2 * 100.0)}')
    UPTIME=\$(uptime -p)
    log "✅ backhaul healthy. CPU: \$CPU%, MEM: \$MEM%, UPTIME: \$UPTIME"
}

check_reboot_required
check_backhaul
EOF

    chmod +x /root/backhaul_monitor.sh
}

# ============ FUNCTION: CREATE SYSTEMD TIMER ============
create_monitor_timer() {
    local interval="$1"
    local api_token="$2"

    cat > /etc/systemd/system/backhaul-monitor.service <<EOF
[Unit]
Description=Backhaul Health Monitor

[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh "$api_token"
EOF

    cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Run backhaul monitor every $interval

[Timer]
OnBootSec=2min
OnUnitActiveSec=$interval
Unit=backhaul-monitor.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now backhaul-monitor.timer
}

# ============ MENU ============
while true; do
    echo "\n${BOLD}${BLUE}==== BACKHAUL MANAGER v1.1 ====${RESET}"
    echo "1) Install Backhaul - Iran"
    echo "2) Install Backhaul - Kharej"
    echo "3) Setup Monitoring Only"
    echo "4) View Monitoring Logs"
    echo "5) Check Status"
    echo "6) Fast Reconnect"
    echo "7) Uninstall All"
    echo "8) Update Monitor"
    echo "0) Exit"
    echo -n "${YELLOW}Enter your choice: ${RESET}"
    read CHOICE

    case "$CHOICE" in
        1)
            echo "Iran installation (Coming next in full script)"
            ;;
        2)
            echo "Kharej installation (Coming next in full script)"
            ;;
        3)
            echo -n "How often to check? (default 2m): "
            read interval
            [ -z "$interval" ] && interval="2m"
            echo -n "Enter Telegram Bot API URL (or leave empty): "
            read telegram_api
            clear_old_cron
            create_monitor_script
            create_monitor_timer "$interval" "$telegram_api"
            echo "${GREEN}Monitoring setup completed.${RESET}"
            ;;
        4)
            echo "${BLUE}Showing last 20 log entries:${RESET}"
            tail -n 20 "$LOG_FILE"
            ;;
        5)
            systemctl status backhaul.service
            ;;
        6)
            echo "Restarting backhaul.service..."
            systemctl restart backhaul.service
            ;;
        7)
            echo "Stopping services and deleting..."
            systemctl stop backhaul.service backhaul-monitor.timer backhaul-monitor.service
            systemctl disable backhaul.service backhaul-monitor.timer backhaul-monitor.service
            rm -f /etc/systemd/system/backhaul* /root/backhaul_monitor.sh "$LOG_FILE" "$EXEC_LOG"
            echo "${GREEN}Uninstall complete.${RESET}"
            ;;
        8)
            echo "Updating monitor script..."
            create_monitor_script
            systemctl restart backhaul-monitor.timer
            echo "${GREEN}Monitor script updated.${RESET}"
            ;;
        0)
            echo "${BLUE}Goodbye!${RESET}"
            break
            ;;
        *)
            echo "${RED}Invalid choice!${RESET}"
            ;;
    esac
done

# ============ FOOTER ============
echo "\n${BOLD}${GREEN}Done. Thank you!${RESET}"
echo "${BOLD}${BLUE}EDITED BY PILOT CODE${RESET}"
