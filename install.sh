#!/bin/bash

# =========================================================
# Project:      TUNEL-STAR (Ultimate Tunnel Manager)
# Author:       Moriistar
# GitHub:       https://github.com/Moriistar
# Description:  Auto-install HAProxy, IPv6 & VXLAN Tunnels
# Language:     English
# =========================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[Error] Please run this script as root.${NC}"
   exit 1
fi

# --- Logo ---
show_header() {
    clear
    echo -e "${CYAN}"
    echo "  _______                     __       ______ __                  "
    echo " /_  __(_)_  ______  ___     / /      / __/ //_/____ ______       "
    echo "  / / / / / / / __ \/ _ \   / /_______\ \/ __/ __  // ___/       "
    echo " / / / / /_/ / / / /  __/  / /_____/___/ / /_/ /_/ / /           "
    echo "/_/ /_/\__,_/_/ /_/\___/  /_/     /_____/\__/\__,_/_/            "
    echo -e "${NC}"
    echo -e "   ${YELLOW}PROJECT: TUNEL-STAR${NC} | ${GREEN}By MORIISTAR${NC}"
    echo -e "   ${BLUE}v3.0 - Fully Automated / English Version${NC}"
    echo "========================================================"
}

# --- Auto Install Dependencies ---
install_deps() {
    echo -e "${BLUE}[Wait] Checking and installing system dependencies...${NC}"
    # Quiet update
    apt-get update -qq > /dev/null 2>&1
    
    deps=("curl" "jq" "net-tools" "iproute2" "iptables" "nano" "haproxy")
    
    for pkg in "${deps[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW} -> Installing: $pkg${NC}"
            apt-get install -y -qq $pkg > /dev/null 2>&1
        fi
    done
    
    # Netplan specific check
    if ! command -v netplan &> /dev/null; then
         apt-get install -y -qq netplan.io > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}[OK] All dependencies are ready.${NC}"
    sleep 1
}

# --- Advisor (Smart Suggestion) ---
show_advice() {
    echo -e "\n${MAGENTA}--- Tunnel Advisor ---${NC}"
    echo -e "${GREEN}1. HAProxy (Recommended):${NC} Best for standard Web/V2Ray (TCP) relay. Low CPU usage, very stable."
    echo -e "${GREEN}2. IPv6 Tunnel (6to4):${NC} Best for bypassing IP filtering. Creates a tunnel inside IPv4."
    echo -e "${GREEN}3. VXLAN (Layer 2):${NC} Best if you need to connect two servers as if they are on the same LAN."
    echo -e "--------------------------------------------------------"
}

# =========================================================
#                 MODULE 1: HAProxy
# =========================================================
install_haproxy() {
    echo -e "${BLUE}[Wait] Configuring HAProxy...${NC}"
    
    echo -e "${YELLOW}>> HAProxy Setup <<${NC}"
    read -p "Remote Server IP (Destination): " REMOTE_IP
    read -p "Local Ports to Forward (e.g., 443,80,2082 - separate with comma): " PORTS_STR
    
    CFG="/etc/haproxy/haproxy.cfg"
    
    # Base Config
    cat <<EOL > $CFG
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

EOL

    # Loop through ports
    IFS=',' read -ra PORT_LIST <<< "$PORTS_STR"
    for port in "${PORT_LIST[@]}"; do
        cat <<EOL >> $CFG
frontend ft_$port
    bind *:$port
    default_backend bk_$port

backend bk_$port
    server srv1 $REMOTE_IP:$port maxconn 2048
EOL
    done

    systemctl restart haproxy
    echo -e "${GREEN}[Success] HAProxy Tunnel is active!${NC}"
}

# =========================================================
#                 MODULE 2: IPv6 (Netplan/SIT)
# =========================================================
install_ipv6() {
    echo -e "${YELLOW}>> IPv6 6to4 Tunnel Setup <<${NC}"
    echo "1) I am the IRAN Server (Local)"
    echo "2) I am the KHAREJ Server (Remote)"
    read -p "Select your role (1 or 2): " SIDE

    read -p "IRAN Server IPv4: " IRAN_IP
    read -p "KHAREJ Server IPv4: " KHAREJ_IP
    
    # Generate random ULA prefix
    PREFIX="fd$(printf '%x' $((RANDOM%256))):$(printf '%x' $((RANDOM%65536)))"
    
    if [[ "$SIDE" == "1" ]]; then
        LOCAL=$IRAN_IP
        REMOTE=$KHAREJ_IP
        MY_IPV6="${PREFIX}::1/64"
        PEER_IPV6="${PREFIX}::2"
    else
        LOCAL=$KHAREJ_IP
        REMOTE=$IRAN_IP
        MY_IPV6="${PREFIX}::2/64"
        PEER_IPV6="${PREFIX}::1"
    fi

    echo -e "${BLUE}[Wait] Applying Network Configuration...${NC}"
    
    NETPLAN_FILE="/etc/netplan/tunel-star-6to4.yaml"
    
    cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  tunnels:
    tun6to4:
      mode: sit
      local: $LOCAL
      remote: $REMOTE
      addresses:
        - $MY_IPV6
EOF

    netplan apply
    
    # Create Keepalive Service
    CONNECTOR="/root/tunel-star-keepalive.sh"
    cat > "$CONNECTOR" <<EOL
#!/bin/bash
while true; do
    ping -6 -c 3 $PEER_IPV6 > /dev/null 2>&1
    sleep 5
done
EOL
    chmod +x "$CONNECTOR"

    SERVICE_FILE="/etc/systemd/system/tunel-star-ipv6.service"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tunel-Star IPv6 Keepalive
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash $CONNECTOR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now tunel-star-ipv6

    echo -e "${GREEN}[Success] IPv6 Tunnel Established.${NC}"
    echo -e "Your IPv6: ${CYAN}$MY_IPV6${NC}"
    echo -e "${RED}IMPORTANT:${NC} You must run this script on the OTHER server with the opposite role."
    echo -e "Keep the generated prefix if needed manually: $PREFIX"
}

# =========================================================
#                 MODULE 3: VXLAN (Systemd)
# =========================================================
install_vxlan() {
    echo -e "${YELLOW}>> VXLAN Layer 2 Setup <<${NC}"
    read -p "Remote Server IP (The other side): " REMOTE_IP
    read -p "Tunnel Internal IP (e.g., 192.168.100.1): " VXLAN_IP
    
    # Auto-detect interface
    INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    
    echo -e "${BLUE}[Wait] Creating Persistent Service...${NC}"
    SERVICE_FILE="/etc/systemd/system/tunel-star-vxlan.service"
    
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Tunel-Star VXLAN Service
After=network.target

[Service]
ExecStartPre=/sbin/ip link add vxlan100 type vxlan id 100 remote $REMOTE_IP local $(hostname -I | awk '{print $1}') dev $INTERFACE dstport 4789
ExecStartPre=/sbin/ip addr add $VXLAN_IP/24 dev vxlan100
ExecStartPre=/sbin/ip link set vxlan100 up
ExecStart=/bin/bash -c "while true; do sleep 3600; done"
ExecStop=/sbin/ip link del vxlan100
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tunel-star-vxlan
    systemctl restart tunel-star-vxlan
    
    # Add Firewall Rules
    iptables -I INPUT -p udp --dport 4789 -j ACCEPT
    
    echo -e "${GREEN}[Success] VXLAN Service Installed & Started.${NC}"
}

# =========================================================
#                 MODULE 4: Utilities (BBR)
# =========================================================
install_bbr() {
    echo -e "${BLUE}[Wait] Enabling Google BBR...${NC}"
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${GREEN}[Success] BBR Enabled.${NC}"
}

uninstall_all() {
    echo -e "${RED}[!] Removing all Tunel-Star configurations...${NC}"
    
    # HAProxy
    apt-get purge -y haproxy > /dev/null 2>&1
    rm -f /etc/haproxy/haproxy.cfg
    
    # IPv6
    rm -f /etc/netplan/tunel-star-6to4.yaml
    systemctl stop tunel-star-ipv6 > /dev/null 2>&1
    systemctl disable tunel-star-ipv6 > /dev/null 2>&1
    rm -f /etc/systemd/system/tunel-star-ipv6.service
    
    # VXLAN
    systemctl stop tunel-star-vxlan > /dev/null 2>&1
    systemctl disable tunel-star-vxlan > /dev/null 2>&1
    rm -f /etc/systemd/system/tunel-star-vxlan.service
    
    systemctl daemon-reload
    netplan apply > /dev/null 2>&1
    
    echo -e "${GREEN}[Done] All services removed.${NC}"
}

# =========================================================
#                 MAIN LOGIC
# =========================================================

install_deps
show_header

echo -e "Hello! I am the ${YELLOW}Tunel-Star${NC} installer bot."
echo -e "I have installed all necessary dependencies for you.\n"

echo "What would you like to do?"
echo "1) Install HAProxy (TCP Tunnel)"
echo "2) Install IPv6 Tunnel (6to4)"
echo "3) Install VXLAN (Layer 2 Tunnel)"
echo "4) Enable Google BBR (Speed Boost)"
echo "5) Uninstall Everything"
echo "6) Help / Advisor"
echo "0) Exit"
echo -e "------------------------------------"
read -p "Your Choice: " choice

case $choice in
    1) install_haproxy ;;
    2) install_ipv6 ;;
    3) install_vxlan ;;
    4) install_bbr ;;
    5) uninstall_all ;;
    6) show_advice; read -p "Press Enter to return..." ;;
    0) exit 0 ;;
    *) echo "Invalid option!" ;;
esac

echo -e "\n${CYAN}Operation Completed. Thank you for using Tunel-Star.${NC}"
