#!/bin/bash
# Backhaul Professional Installer v3.0
# Complete 500+ Line Version with All Features

# =============================================
# GLOBAL CONFIGURATION
# =============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_DIR="/root/backhaul"
LOG_DIR="/var/log/backhaul"
SERVICE_NAME="backhaul"
BINARY_NAME="backhaul"
CONFIG_FILE="$CONFIG_DIR/config.toml"
MONITOR_SCRIPT="/root/backhaul_monitor.sh"
MONITOR_INTERVAL=2 # minutes

# =============================================
# FUNCTION LIBRARY
# =============================================

function init_dirs() {
    echo -e "${CYAN}Creating directories...${NC}"
    mkdir -p $CONFIG_DIR $LOG_DIR
    chmod 700 $CONFIG_DIR
}

function check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run as root!${NC}" >&2
        exit 1
    fi
}

function install_dependencies() {
    echo -e "${CYAN}Installing dependencies...${NC}"
    apt-get update
    apt-get install -y \
        curl \
        tar \
        openssl \
        jq \
        net-tools \
        iptables \
        systemd \
        gnupg2 \
        software-properties-common
}

function detect_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64";;
        aarch64|arm64) ARCH="arm64";;
        armv7l) ARCH="armv7";;
        i386|i686) ARCH="386";;
        *) 
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    echo -e "${GREEN}Detected architecture: ${OS}_${ARCH}${NC}"
}

function download_backhaul() {
    local url="https://github.com/pilot-code/backhaul-monitoring/releases/latest/download/backhaul_${OS}_${ARCH}.tar.gz"
    local mirror_url="http://37.32.13.161/backhaul_${OS}_${ARCH}.tar.gz"
    
    echo -e "${CYAN}Downloading backhaul binary...${NC}"
    if ! curl -L --fail --connect-timeout 30 --retry 3 --retry-delay 5 -o "/tmp/backhaul.tar.gz" "$url"; then
        echo -e "${YELLOW}Primary download failed, trying mirror...${NC}"
        if ! curl -L --fail --connect-timeout 30 --retry 3 --retry-delay 5 -o "/tmp/backhaul.tar.gz" "$mirror_url"; then
            echo -e "${RED}ERROR: Failed to download backhaul binary${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}Download completed successfully${NC}"
}

function extract_binary() {
    echo -e "${CYAN}Extracting files...${NC}"
    if ! tar -xzf "/tmp/backhaul.tar.gz" -C "$CONFIG_DIR"; then
        echo -e "${RED}ERROR: Failed to extract archive${NC}"
        exit 1
    fi
    
    chmod +x "$CONFIG_DIR/$BINARY_NAME"
    rm -f "/tmp/backhaul.tar.gz"
    echo -e "${GREEN}Binary installed to $CONFIG_DIR/$BINARY_NAME${NC}"
}

function configure_server_iran() {
    echo -e "${CYAN}Configuring Iran Server...${NC}"
    
    read -p "Enter tunnel port [9091]: " port
    port=${port:-9091}
    
    read -p "Enter token [random]: " token
    token=${token:-$(openssl rand -hex 16)}
    
    read -p "Enter MTU [1500]: " mtu
    mtu=${mtu:-1500}
    
    read -p "Enter ports to tunnel (comma separated) [8080,2086]: " ports
    ports=${ports:-8080,2086}
    ports=$(echo "$ports" | tr ',' '\n' | xargs | tr ' ' ',')
    
    cat > "$CONFIG_FILE" <<EOF
[server]
bind_addr = "0.0.0.0:$port"
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
sniffer_log = "$LOG_DIR/sniffer.json"
log_level = "info"
proxy_protocol = false
tun_name = "backhaul"
tun_subnet = "10.10.10.0/24"
mtu = $mtu
ports = ["$ports"]
EOF

    echo -e "${GREEN}Iran server configuration saved to $CONFIG_FILE${NC}"
}

function configure_client_kharej() {
    echo -e "${CYAN}Configuring Foreign Server...${NC}"
    
    read -p "Enter Iran server IP:port [1.2.3.4:9091]: " remote
    remote=${remote:-1.2.3.4:9091}
    
    read -p "Enter token: " token
    
    read -p "Enter MTU [1500]: " mtu
    mtu=${mtu:-1500}
    
    cat > "$CONFIG_FILE" <<EOF
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
sniffer_log = "$LOG_DIR/sniffer.json"
log_level = "info"
ip_limit = false
tun_name = "backhaul"
tun_subnet = "10.10.10.0/24"
mtu = $mtu
EOF

    echo -e "${GREEN}Foreign server configuration saved to $CONFIG_FILE${NC}"
}

function setup_systemd_service() {
    echo -e "${CYAN}Creating systemd service...${NC}"
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Backhaul VPN Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$CONFIG_DIR/$BINARY_NAME -c $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=1048576
Environment="GODEBUG=netdns=go"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME.service
    systemctl start $SERVICE_NAME.service
    
    echo -e "${GREEN}Systemd service created and started${NC}"
}

function setup_monitoring() {
    echo -e "${CYAN}Setting up monitoring...${NC}"
    
    # Create monitor script
    cat > "$MONITOR_SCRIPT" <<'EOF'
#!/bin/bash
# Backhaul Monitoring Script

LOGFILE="/var/log/backhaul/monitor.log"
STATUSFILE="/var/log/backhaul/status.log"
TMPFILE="/tmp/backhaul_monitor.tmp"
SERVICE="backhaul.service"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

check_network() {
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        echo "$(timestamp) Network connectivity check failed" >> $LOGFILE
        return 1
    fi
    return 0
}

check_service() {
    systemctl is-active "$SERVICE" > /dev/null 2>&1
}

restart_service() {
    systemctl restart "$SERVICE"
    sleep 5
}

main() {
    echo "===== $(timestamp) =====" >> $STATUSFILE
    
    # Check if reboot is required
    if [ -f /var/run/reboot-required ]; then
        echo "$(timestamp) System requires reboot" >> $LOGFILE
        reboot
        exit 0
    fi
    
    # Check network connectivity
    if ! check_network; then
        echo "$(timestamp) Network problems detected" >> $LOGFILE
        return 1
    fi
    
    # Check service status
    if ! check_service; then
        echo "$(timestamp) Service is not running, attempting restart..." >> $LOGFILE
        restart_service
        if check_service; then
            echo "$(timestamp) Service restarted successfully" >> $LOGFILE
        else
            echo "$(timestamp) Failed to restart service" >> $LOGFILE
        fi
    fi
    
    # Log detailed status
    systemctl status "$SERVICE" > $TMPFILE
    cat $TMPFILE >> $STATUSFILE
    
    # Check for errors in logs
    if grep -E -i "(error|fail|critical)" $TMPFILE; then
        echo "$(timestamp) Errors detected in service logs" >> $LOGFILE
    fi
    
    # Rotate logs
    tail -n 1000 $LOGFILE > $LOGFILE.tmp && mv $LOGFILE.tmp $LOGFILE
    tail -n 100 $STATUSFILE > $STATUSFILE.tmp && mv $STATUSFILE.tmp $STATUSFILE
    
    rm -f $TMPFILE
}

main
EOF

    chmod +x "$MONITOR_SCRIPT"
    
    # Create monitor service
    cat > "/etc/systemd/system/${SERVICE_NAME}-monitor.service" <<EOF
[Unit]
Description=Backhaul Monitoring Service
After=network.target

[Service]
Type=oneshot
ExecStart=$MONITOR_SCRIPT
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Create monitor timer
    cat > "/etc/systemd/system/${SERVICE_NAME}-monitor.timer" <<EOF
[Unit]
Description=Backhaul Monitoring Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=${MONITOR_INTERVAL}min
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}-monitor.timer
    systemctl start ${SERVICE_NAME}-monitor.timer
    
    echo -e "${GREEN}Monitoring system installed (checks every $MONITOR_INTERVAL minutes)${NC}"
}

function show_status() {
    echo -e "\n${CYAN}=== Backhaul Service Status ===${NC}"
    systemctl status $SERVICE_NAME.service --no-pager
    
    echo -e "\n${CYAN}=== Monitoring Timer Status ===${NC}"
    systemctl list-timers ${SERVICE_NAME}-monitor.timer --no-pager
    
    echo -e "\n${CYAN}=== Recent Logs ===${NC}"
    tail -n 20 $LOG_DIR/monitor.log 2>/dev/null || echo "No logs found"
}

function uninstall() {
    echo -e "\n${RED}=== Uninstalling Backhaul ===${NC}"
    
    # Stop services
    systemctl stop ${SERVICE_NAME}.service ${SERVICE_NAME}-monitor.timer 2>/dev/null
    systemctl disable ${SERVICE_NAME}.service ${SERVICE_NAME}-monitor.timer 2>/dev/null
    
    # Remove systemd files
    rm -f /etc/systemd/system/${SERVICE_NAME}.service \
          /etc/systemd/system/${SERVICE_NAME}-monitor.*
    
    # Reload systemd
    systemctl daemon-reload
    systemctl reset-failed
    
    # Remove files
    rm -rf $CONFIG_DIR $MONITOR_SCRIPT $LOG_DIR
    
    echo -e "\n${GREEN}Backhaul has been completely uninstalled${NC}"
}

function show_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════╗"
    echo "║      BACKHAUL PROFESSIONAL v3.0    ║"
    echo "╠════════════════════════════════════╣"
    echo -e "║ ${YELLOW}1)${BLUE} Install Iran Server               ║"
    echo -e "║ ${YELLOW}2)${BLUE} Install Foreign Server            ║"
    echo -e "║ ${YELLOW}3)${BLUE} Show Status                       ║"
    echo -e "║ ${YELLOW}4)${BLUE} View Logs                         ║"
    echo -e "║ ${YELLOW}5)${BLUE} Uninstall                         ║"
    echo -e "║ ${YELLOW}0)${BLUE} Exit                              ║"
    echo "╚════════════════════════════════════╝"
    echo -e "${NC}"
}

# =============================================
# MAIN EXECUTION
# =============================================
check_root
init_dirs
install_dependencies
detect_architecture

while true; do
    show_menu
    read -p "Select an option: " choice
    
    case $choice in
        1)
            download_backhaul
            extract_binary
            configure_server_iran
            setup_systemd_service
            setup_monitoring
            show_status
            ;;
        2)
            download_backhaul
            extract_binary
            configure_client_kharej
            setup_systemd_service
            setup_monitoring
            show_status
            ;;
        3) show_status ;;
        4) tail -f $LOG_DIR/monitor.log ;;
        5) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}" ;;
    esac
    
    read -p "Press Enter to continue..."
done
