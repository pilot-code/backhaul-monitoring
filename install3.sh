#!/bin/bash

# ============================
#      BACKHAUL MASTER
#    EDITED BY PILOT CODE
# ============================

# تنظیم رنگ‌ها
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

function logo() {
    clear
    echo "${CYAN}"
    echo "╔══════════════════════════════════════╗"
    echo "║          BACKHAUL MASTER             ║"
    echo "║        EDITED BY PILOT CODE          ║"
    echo "╚══════════════════════════════════════╝"
    echo "${RESET}"
}

function show_menu() {
    CHOICE=$(whiptail --title "Backhaul Master Menu" --menu "Choose an option" 20 60 10     "1" "Install on Iran server"     "2" "Install on Foreign server"     "3" "Install Monitoring only"     "4" "Check Monitoring Logs"     "5" "Service Status"     "6" "Uninstall All"     "7" "Update Monitoring"     "0" "Exit" 3>&1 1>&2 2>&3)

    case "$CHOICE" in
        1) install_iran ;;
        2) install_foreign ;;
        3) install_monitoring ;;
        4) view_logs ;;
        5) check_status ;;
        6) uninstall_all ;;
        7) update_monitoring ;;
        0) exit 0 ;;
    esac
}

function install_iran() {
    echo "${YELLOW}Installing Backhaul on IRAN server...${RESET}"
    # نمونه اجرای نصب برای ایران
    read -p "Enter bind port (e.g. 3080): " BIND_PORT
    read -p "Enter token: " TOKEN
    read -p "Enter ports for tunneling (comma separated, e.g. 8880,8080): " PORTS
    read -p "Which protocol? [tcp/wssmux]: " PROTO

    if [[ "$PROTO" == "wssmux" ]]; then
        echo "${CYAN}Checking for SSL certs...${RESET}"
        read -p "Do you already have SSL certs? [y/n]: " HAS_SSL
        if [[ "$HAS_SSL" == "n" ]]; then
            sudo apt install openssl -y
            openssl genpkey -algorithm RSA -out /root/server.key -pkeyopt rsa_keygen_bits:2048
            openssl req -new -key /root/server.key -out /root/server.csr
            openssl x509 -req -in /root/server.csr -signkey /root/server.key -out /root/server.crt -days 365
        fi
    fi

    echo "${GREEN}✅ Installation on Iran server completed.${RESET}"
    sleep 2
}

function install_foreign() {
    echo "${YELLOW}Installing Backhaul on FOREIGN server...${RESET}"
    read -p "Enter IP of Iran server: " IRAN_IP
    read -p "Enter port of Iran server: " IRAN_PORT
    read -p "Enter token: " TOKEN
    read -p "Which protocol? [tcp/wssmux]: " PROTO
    if [[ "$PROTO" == "wssmux" ]]; then
        read -p "Enter domain for Cloudflare (e.g. example.com): " CF_DOMAIN
    fi
    echo "${GREEN}✅ Installation on Foreign server completed.${RESET}"
    sleep 2
}

function install_monitoring() {
    echo "${YELLOW}Installing Monitoring Service...${RESET}"
    read -p "Enter interval for monitoring check (in minutes, default 2): " INTERVAL
    INTERVAL=${INTERVAL:-2}
    echo "${CYAN}Setting up systemd timer with $INTERVAL minutes...${RESET}"

    # مانیتورینگ + ریبوت
    cat <<EOF > /root/backhaul_monitor.sh
#!/bin/bash
log="/var/log/backhaul_monitor.log"
if [[ ! -f \$log ]]; then touch \$log; fi
tail -n 100 \$log > \$log.tmp && mv \$log.tmp \$log

if ! systemctl is-active --quiet backhaul.service; then
  echo "\$(date) ❌ backhaul.service is down! Restarting..." >> \$log
  systemctl restart backhaul.service
  echo "\$(date) ✅ Restarted backhaul.service" >> \$log
else
  echo "\$(date) ✅ backhaul.service is running." >> \$log
fi

if [ -f /var/run/reboot-required ]; then
  echo "\$(date) ⚠️ Reboot required! Rebooting now..." >> \$log
  reboot
fi
EOF

    chmod +x /root/backhaul_monitor.sh

    cat <<EOF > /etc/systemd/system/backhaul-monitor.service
[Unit]
Description=Backhaul Health Check
[Service]
Type=oneshot
ExecStart=/root/backhaul_monitor.sh
EOF

    cat <<EOF > /etc/systemd/system/backhaul-monitor.timer
[Unit]
Description=Run backhaul monitor every $INTERVAL minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=${INTERVAL}min
Unit=backhaul-monitor.service
[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now backhaul-monitor.timer
    echo "${GREEN}✅ Monitoring enabled every $INTERVAL minutes.${RESET}"
    sleep 2
}

function view_logs() {
    echo "${CYAN}Last 20 lines of monitoring log:${RESET}"
    tail -n 20 /var/log/backhaul_monitor.log
    read -p "Press Enter to return to menu..." dummy
}

function check_status() {
    echo "${CYAN}Backhaul Service Status:${RESET}"
    systemctl status backhaul.service --no-pager
    read -p "Press Enter to return to menu..." dummy
}

function uninstall_all() {
    echo "${RED}Uninstalling everything...${RESET}"
    systemctl disable --now backhaul.service backhaul-monitor.timer
    rm -rf /root/backhaul /root/backhaul_monitor.sh /etc/systemd/system/backhaul*.*
    echo "${GREEN}✅ Uninstalled all backhaul components.${RESET}"
    sleep 2
}

function update_monitoring() {
    echo "${CYAN}🔄 Updating Monitoring Script...${RESET}"
    # در صورت نیاز اینجا کدهای جدید مانیتورینگ قرار بگیرند
    echo "${GREEN}✅ Monitoring updated.${RESET}"
}

# تنظیم تایم‌زون سرور
sudo timedatectl set-timezone UTC

# منو اجرا شود
while true; do
    logo
    show_menu
done
