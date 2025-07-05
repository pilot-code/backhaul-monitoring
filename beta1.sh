#!/bin/bash
# Backhaul Installation Script v1.4
# Complete with: Installation, Monitoring, Uninstall, and Color Output

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/root/backhaul"
CONFIG_FILE="$CONFIG_DIR/config.toml"
LOG_DIR="/var/log/backhaul"
GITHUB_URL="https://raw.githubusercontent.com/pilot-code/backhaul-monitoring/main"
IRAN_MIRROR="http://37.32.13.161"

# Main Menu
show_menu() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════╗"
    echo "║       BACKHAUL TOOL v1.4     ║"
    echo "╠══════════════════════════════╣"
    echo -e "║ ${YELLOW}1)${CYAN} Install Iran Server          ║"
    echo -e "║ ${YELLOW}2)${CYAN} Install Foreign Server       ║"
    echo -e "║ ${YELLOW}3)${CYAN} Install Only Monitoring      ║"
    echo -e "║ ${YELLOW}4)${CYAN} Check Monitoring Log         ║"
    echo -e "║ ${YELLOW}5)${CYAN} Check Service Status         ║"
    echo -e "║ ${YELLOW}6)${CYAN} ${RED}Uninstall Backhaul${CYAN}          ║"
    echo -e "║ ${YELLOW}0)${CYAN} Exit                        ║"
    echo "╚══════════════════════════════╝"
    echo -e "${NC}"
    read -p "Select an option: " choice
    case $choice in
        1) install_server_iran;;
        2) install_server_kharej;;
        3) install_monitoring;;
        4) show_logs;;
        5) show_status;;
        6) uninstall;;
        0) exit 0;;
        *) echo -e "${RED}Invalid option!${NC}"; sleep 1;;
    esac
}

# Installation Functions
install_server_iran() {
    echo -e "\n${CYAN}=== Iran Server Installation ===${NC}"
    
    # Get configuration
    read -p "Tunnel Port (default: 9091): " port
    port=${port:-9091}
    read -p "Token: " token
    read -p "MTU (default: 1500): " mtu
    mtu=${mtu:-1500}
    read -p "Ports to tunnel (comma separated, e.g. 8080,2086): " ports
    ports=$(echo $ports | tr ',' '\n' | xargs | tr ' ' ',')

    # Create config
    mkdir -p $CONFIG_DIR
    cat > $CONFIG_FILE <<EOF
[server]
bind_addr = ":$port"
transport = "tcp"
accept_udp = false
token = "$token"
keepalive_period = 20
nodelay = false
channel_size = 2048
heartbeat = 20
mux_con = 8
mux_version = 2
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 2000000
sniffer = false
web_port = 0
sniffer_log = "/root/log.json"
log_level = "info"
proxy_protocol= false
tun_name = "backhaul"
tun_subnet = "10.10.10.0/24"
mtu = $mtu
ports = ["$ports"]
EOF

    echo -e "${GREEN}✓ Config created at $CONFIG_FILE${NC}"
    setup_service
    install_monitoring
}

install_server_kharej() {
    echo -e "\n${CYAN}=== Foreign Server Installation ===${NC}"
    
    # Get configuration
    read -p "Iran Server IP:Port (e.g. 1.2.3.4:9091): " remote
    read -p "Token: " token
    read -p "MTU (default: 1500): " mtu
    mtu=${mtu:-1500}

    # Create config
    mkdir -p $CONFIG_DIR
    cat > $CONFIG_FILE <<EOF
[client]
remote_addr = "$remote"
transport = "tcp"
token = "$token"
connection_pool = 24
aggressive_pool = false
keepalive_period = 20
nodelay = true
retry_interval = 3
dial_timeout = 10
mux_version = 2
mux_framesize = 32768
mux_recievebuffer = 4194304
mux_streambuffer = 2000000
sniffer = false
web_port = 0
sniffer_log = "/root/log.json"
log_level = "info"
ip_limit= false
tun_name = "backhaul"
tun_subnet = "10.10.10.0/24"
mtu = $mtu
EOF

    echo -e "${GREEN}✓ Config created at $CONFIG_FILE${NC}"
    setup_service
    install_monitoring
}

setup_service() {
    # Download binary based on architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64";;
        aarch64|arm64) ARCH="arm64";;
        *) echo -e "${RED}Unsupported architecture!${NC}"; exit 1;;
    esac

    FILE="backhaul_$(uname -s | tr '[:upper:]' '[:lower:]')_$ARCH.tar.gz"
    
    echo -e "${CYAN}Downloading backhaul binary...${NC}"
    if ! curl -sL "$GITHUB_URL/$FILE" -o $FILE; then
        echo -e "${YELLOW}Primary download failed, trying mirror...${NC}"
        curl -sL "$IRAN_MIRROR/$FILE" -o $FILE || {
            echo -e "${RED}Download failed!${NC}";
            exit 1;
        }
    fi
    
    tar -xzf $FILE -C $CONFIG_DIR
    rm $FILE

    # Create systemd service
    cat > /etc/systemd/system/backhaul.service <<EOF
[Unit]
Description=Backhaul Service
After=network.target

[Service]
Type=simple
ExecStart=$CONFIG_DIR/backhaul -c $CONFIG_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now backhaul.service
    echo -e "${GREEN}✓ Backhaul service installed and started${NC}"
}

# Monitoring System
install_monitoring() {
    echo -e "\n${CYAN}=== Monitoring Setup ===${NC}"
    read -p "Check interval (minutes, default 2): " interval
    interval=${interval:-2}

    mkdir -p $LOG_DIR
    cat > /root/backhaul_monitor.sh <<'EOF'
#!/bin/bash
# Monitoring Script
LOGFILE="/var/log/backhaul/monitor.log"
STATUS_LOG="/var/log/backhaul/status.log"
TMP_LOG="/tmp/backhaul_monitor.tmp"

check_time=$(date '+%Y-%m-%d %H:%M:%S')
status=$(systemctl is-active backhaul.service)

if [ "$status" != "active" ]; then
    echo "$check_time - Service is DOWN! Restarting..." >> $LOGFILE
    systemctl restart backhaul.service
    sleep 2
    new_status=$(systemctl is-active backhaul.service)
    echo "$check_time - Restart result: $new_status" >> $LOGFILE
fi

systemctl status backhaul.service > $STATUS_LOG
EOF

    chmod +x /root/backhaul_monitor.sh

    # Create systemd timer
    cat > /etc/systemd/system/backhaul-monitor.timer <<EOF
[Unit]
Description=Backhaul Monitoring Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now backhaul-monitor.timer
    echo -e "${GREEN}✓ Monitoring installed (checks every $interval minutes)${NC}"
}

# Uninstaller
uninstall() {
    echo -e "\n${RED}=== Uninstalling Backhaul ===${NC}"
    
    systemctl stop backhaul.service backhaul-monitor.timer 2>/dev/null
    systemctl disable backhaul.service backhaul-monitor.timer 2>/dev/null
    rm -f /etc/systemd/system/backhaul.service /etc/systemd/system/backhaul-monitor.*
    systemctl daemon-reload
    
    rm -rf $CONFIG_DIR /root/backhaul_monitor.sh $LOG_DIR
    
    echo -e "${GREEN}✓ Backhaul completely uninstalled${NC}"
}

# Status Functions
show_logs() {
    echo -e "\n${CYAN}=== Monitoring Log ===${NC}"
    [ -f "$LOG_DIR/monitor.log" ] && tail -n 20 $LOG_DIR/monitor.log || echo "No logs found"
}

show_status() {
    echo -e "\n${CYAN}=== Service Status ===${NC}"
    [ -f "$LOG_DIR/status.log" ] && cat $LOG_DIR/status.log || systemctl status backhaul.service
}

# Main Loop
while true; do
    show_menu
    read -p "Press Enter to continue..."
done
