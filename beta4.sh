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

install_backhaul() {
    local SRV_TYPE="$1"
    sudo timedatectl set-timezone UTC

    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        i386|i686) ARCH="386" ;;
        *) echo "Unsupported architecture!"; exit 1 ;;
    esac
    FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"

    curl -L -o "$FILE_NAME" "$MY_GITHUB_URL/$FILE_NAME" || curl -L -o "$FILE_NAME" "$IRAN_URL/$FILE_NAME"

    mkdir -p /root/backhaul
    tar -xzf "$FILE_NAME" -C /root/backhaul && rm -f "$FILE_NAME"

    TUNNEL_TYPE="tcp"
    BKTOKEN="default_secure_token"

    if [ "$SRV_TYPE" = "server" ]; then
        TUNNEL_PORT="3080"
        PORTS_RAW="8080,2086"
        PORTS=$(echo "$PORTS_RAW" | tr -d ' ' | sed 's/,/","/g')
        BACKHAUL_CONFIG="[server]\nbind_addr = \"0.0.0.0:$TUNNEL_PORT\"\ntransport = \"tcp\"\naccept_udp = false\ntoken = \"$BKTOKEN\"\nkeepalive_period = 75\nnodelay = true\nheartbeat = 40\nchannel_size = 2048\nsniffer = true\nweb_port = 2060\nsniffer_log = \"/root/backhaul.json\"\nlog_level = \"info\"\nports = [\"$PORTS\"]"
    else
        IRAN_IP="37.32.13.161"
        TUNNEL_PORT="3080"
        BACKHAUL_CONFIG="[client]\nremote_addr = \"$IRAN_IP:$TUNNEL_PORT\"\ntransport = \"tcp\"\ntoken = \"$BKTOKEN\"\nconnection_pool = 8\naggressive_pool = false\nkeepalive_period = 75\ndial_timeout = 10\nnodelay = true\nretry_interval = 3\nsniffer = true\nweb_port = 2060\nsniffer_log = \"/root/backhaul.json\"\nlog_level = \"info\""
    fi

    echo "$BACKHAUL_CONFIG" > /root/backhaul/config.toml

    cat <<EOF | sudo tee /etc/systemd/system/backhaul.service > /dev/null
[Unit]
Description=Backhaul Reverse Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/root/backhaul/backhaul -c /root/backhaul/config.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now backhaul.service
}

install_monitoring() {
    MON_MIN=2
    TUNNEL_HOST="127.0.0.1"
    TUNNEL_PORT="3080"

    cat <<EOM > /root/backhaul_monitor.sh
#!/bin/bash
LOGFILE="/var/log/backhaul_monitor.log"
SERVICENAME="backhaul.service"
TIME=\$(date '+%Y-%m-%d %H:%M:%S')

nc -z -w3 $TUNNEL_HOST $TUNNEL_PORT || systemctl restart \$SERVICENAME
ping -c1 -W1 $TUNNEL_HOST >/dev/null || systemctl restart \$SERVICENAME

journalctl -u \$SERVICENAME --since "1 minute ago" | grep -E '(closed|shutting down|inactive)' && systemctl restart \$SERVICENAME

echo "\$TIME check completed" >> \$LOGFILE
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
Description=Run Backhaul Health Check every ${MON_MIN} minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=${MON_MIN}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now backhaul-monitor.timer
}


while true; do
    show_menu
    read -r opt
    case "$opt" in
        1)
            install_backhaul server
            install_monitoring
            ;;
        2)
            install_backhaul client
            install_monitoring
            ;;
        3)
            install_monitoring
            ;;
        4)
            check_monitor_log
            ;;
        5)
            check_service_status
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Option not recognized! Try again." ;;
    esac
done
