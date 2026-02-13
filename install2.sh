#!/usr/bin/env bash
set -e

clear
echo "========= Reverse SSH PRO Manager ========="
echo "1) Install / Configure (Professional)"
echo "2) Full Remove Everything"
echo "3) Optimize For V2Ray (BBR + TCP)"
read -p "Select option: " OPTION

#############################################
install_pro() {

read -p "Enter IRAN Server IP: " IRAN_IP
read -p "Enter SSH Port (default 2222): " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}

read -p "Enter ports to tunnel (space separated): " PORTS
read -p "Enter PUBLIC ports (open to world): " PUBLIC_PORTS
read -p "Enter IRAN-only ports: " IRAN_ONLY_PORTS

apt update -y
apt install -y autossh ufw fail2ban iptables-persistent

################ FIREWALL ################
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH only from your IP (optional)
read -p "Restrict SSH only to IRAN IP? (y/n): " SSH_LOCK
if [[ "$SSH_LOCK" == "y" ]]; then
    ufw allow from $IRAN_IP to any port $SSH_PORT proto tcp
else
    ufw allow $SSH_PORT/tcp
fi

# Public ports
for p in $PUBLIC_PORTS; do
    ufw allow $p/tcp
done

# Iran-only ports
for p in $IRAN_ONLY_PORTS; do
    ufw allow from $IRAN_IP to any port $p proto tcp
done

# Block SMTP spam
ufw deny 25
ufw deny 465
ufw deny 587

ufw --force enable

################ SSH HARDEN ################
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat >/etc/ssh/sshd_config <<EOF
Port $SSH_PORT
Protocol 2

PermitRootLogin prohibit-password
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes

MaxAuthTries 3
LoginGraceTime 20
MaxSessions 2

ClientAliveInterval 60
ClientAliveCountMax 2

AllowTcpForwarding yes
GatewayPorts yes
X11Forwarding no
AllowAgentForwarding no

LogLevel VERBOSE
EOF

systemctl restart sshd

################ FAIL2BAN ################
cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
findtime = 10m
bantime = 24h
backend = systemd
EOF

systemctl restart fail2ban

################ RATE LIMIT ################
for p in $PUBLIC_PORTS; do
iptables -A INPUT -p tcp --dport $p -m connlimit --connlimit-above 80 -j REJECT
iptables -A INPUT -p tcp --syn --dport $p -m limit --limit 30/second --limit-burst 100 -j ACCEPT
done

netfilter-persistent save

################ AUTOSSH SERVICE ################
cat >/etc/systemd/system/reverse@.service <<EOF
[Unit]
Description=Reverse SSH Tunnel Port %I
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=AUTOSSH_GATETIME=0
ExecStart=/usr/bin/autossh -M 20000 -N \
-o ExitOnForwardFailure=yes \
-o ServerAliveInterval=20 \
-o ServerAliveCountMax=3 \
-o TCPKeepAlive=yes \
-o Compression=no \
-o IPQoS=throughput \
-R 0.0.0.0:%i:localhost:%i root@${IRAN_IP} -p $SSH_PORT

Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

for p in $PORTS; do
    systemctl enable --now reverse@$p
done

echo "Professional installation completed successfully."
}

#############################################
remove_all() {

systemctl stop reverse@* 2>/dev/null || true
systemctl disable reverse@* 2>/dev/null || true

rm -f /etc/systemd/system/reverse@.service
rm -f /etc/fail2ban/jail.local

apt remove -y autossh fail2ban || true
ufw --force disable
iptables -F
netfilter-persistent save

systemctl daemon-reload

echo "All components removed."
}

#############################################
optimize_v2ray() {

cat >/etc/sysctl.d/99-v2ray-tuning.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.somaxconn=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
EOF

sysctl --system

echo "BBR + TCP optimization applied."
}

#############################################

case $OPTION in
1) install_pro ;;
2) remove_all ;;
3) optimize_v2ray ;;
*) echo "Invalid option." ;;
esac
