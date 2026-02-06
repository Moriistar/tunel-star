#!/bin/bash

# =========================================================
# Project:      TUNEL-STAR (Ultimate Tunnel Manager)
# Author:       Moriistar
# GitHub:       https://github.com/Moriistar
# Description:  Auto-install HAProxy, IPv6, VXLAN & GOST
# Version:      4.0 (Full Security Edition)
# =========================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
    echo -e "   ${BLUE}v4.0 - Full Security Edition${NC}"
    echo "========================================================"
}

# --- Auto Install Dependencies ---
install_deps() {
    echo -e "${BLUE}[Wait] Checking system dependencies...${NC}"
    apt-get update -qq > /dev/null 2>&1
    
    deps=("curl" "jq" "net-tools" "iproute2" "iptables" "nano" "haproxy" "wget")
    
    for pkg in "${deps[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW} -> Installing: $pkg${NC}"
            apt-get install -y -qq $pkg > /dev/null 2>&1
        fi
    done
    
    if ! command -v netplan &> /dev/null; then
         apt-get install -y -qq netplan.io > /dev/null 2>&1
    fi
    sleep 1
}

# --- Install GOST (Only if needed) ---
install_gost() {
    if [ ! -f "/usr/local/bin/gost" ]; then
        echo -e "${BLUE}[Wait] Downloading GOST core...${NC}"
        wget -q -O - https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz | gunzip > /usr/local/bin/gost
        chmod +x /usr/local/bin/gost
        echo -e "${GREEN}[OK] GOST Installed.${NC}"
    fi
}

# --- Smart IP Analysis Function ---
analyze_ip() {
    local ip=$1
    local expected_loc=$2 # "IRAN" or "FOREIGN"

    echo -e "${BLUE} > Analyzing IP: $ip ...${NC}"
    
    local api_data=$(curl -s --max-time 5 "http://ip-api.com/json/$ip")
    
    if [[ -z "$api_data" ]] || [[ "$api_data" == *"fail"* ]]; then
        echo -e "${RED}[!] Could not verify IP info (API Offline). Proceeding with caution.${NC}"
        return
    fi

    local country=$(echo "$api_data" | jq -r '.country')
    local isp=$(echo "$api_data" | jq -r '.isp')

    echo -e " ----------------------------------------------"
    echo -e "  ${YELLOW}IP Address:${NC}  $ip"
    echo -e "  ${YELLOW}Location:${NC}    $country"
    echo -e "  ${YELLOW}ISP:${NC}         $isp"
    echo -e " ----------------------------------------------"

    # Logic Check
    if [[ "$expected_loc" == "IRAN" ]]; then
        if [[ "$country" != "Iran" ]]; then
            echo -e "${RED}[WARNING] You said this is IRAN, but IP is in $country!${NC}"
            read -p "Are you sure? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then exit 1; fi
        else
            echo -e "${GREEN}[OK] Confirmed: Iranian IP.${NC}"
        fi
    elif [[ "$expected_loc" == "FOREIGN" ]]; then
        if [[ "$country" == "Iran" ]]; then
            echo -e "${RED}[WARNING] You said this is FOREIGN, but IP is in Iran!${NC}"
            read -p "Are you sure? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then exit 1; fi
        else
            echo -e "${GREEN}[OK] Confirmed: Foreign IP.${NC}"
        fi
    fi
    echo ""
}

# --- Advisor ---
show_advice() {
    echo -e "\n${MAGENTA}--- Tunnel Advisor ---${NC}"
    echo -e "${GREEN}1. HAProxy:${NC} Standard TCP Tunnel. Best for V2Ray. (Low Load)"
    echo -e "${GREEN}2. IPv6 (6to4):${NC} Bypasses IP filtering. Good for blocked IPs."
    echo -e "${GREEN}3. Secure Tunnel (GOST):${NC} Encrypted (TLS). Hardest to detect (Anti-Filter)."
    echo -e "${GREEN}4. VXLAN:${NC} Layer 2 Tunnel. Best for Gaming/VoIP."
    echo -e "--------------------------------------------------------"
}

# =========================================================
#                 MODULE 1: HAProxy
# =========================================================
install_haproxy() {
    echo -e "${YELLOW}>> HAProxy Setup <<${NC}"
    
    read -p "Enter REMOTE Server IP (Kharej): " REMOTE_IP
    analyze_ip "$REMOTE_IP" "FOREIGN"
    
    read -p "Enter Local Ports to Forward (e.g., 443,80,2082): " PORTS_STR
    
    echo -e "${BLUE}[Wait] Configuring HAProxy...${NC}"
    CFG="/etc/haproxy/haproxy.cfg"
    
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
    echo "1) I am the IRAN Server"
    echo "2) I am the FOREIGN Server"
    read -p "Select role (1/2): " SIDE

    read -p "Enter IRAN Server IP: " IRAN_IP
    analyze_ip "$IRAN_IP" "IRAN"

    read -p "Enter FOREIGN Server IP: " KHAREJ_IP
    analyze_ip "$KHAREJ_IP" "FOREIGN"
    
    PREFIX="fd$(printf '%x' $((RANDOM%256))):$(printf '%x' $((RANDOM%65536)))"
    
    if [[ "$SIDE" == "1" ]]; then
        LOCAL=$IRAN_IP; REMOTE=$KHAREJ_IP; MY_IPV6="${PREFIX}::1/64"; PEER_IPV6="${PREFIX}::2"
    else
        LOCAL=$KHAREJ_IP; REMOTE=$IRAN_IP; MY_IPV6="${PREFIX}::2/64"; PEER_IPV6="${PREFIX}::1"
    fi

    echo -e "${BLUE}[Wait] Applying Network Config...${NC}"
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
    
    # Keepalive
    CONNECTOR="/root/tunel-star-keepalive.sh"
    cat > "$CONNECTOR" <<EOL
#!/bin/bash
while true; do ping -6 -c 3 $PEER_IPV6 > /dev/null 2>&1; sleep 5; done
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
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now tunel-star-ipv6
    echo -e "${GREEN}[Success] IPv6 Tunnel Established. IP: $MY_IPV6${NC}"
}

# =========================================================
#                 MODULE 3: Secure Tunnel (GOST)
# =========================================================
install_secure_tunnel() {
    install_gost
    echo -e "${YELLOW}>> Secure Encrypted Tunnel (GOST+TLS) <<${NC}"
    echo "1) I am IRAN Server"
    echo "2) I am FOREIGN Server"
    read -p "Role: " ROLE

    if [[ "$ROLE" == "2" ]]; then
        # Foreign
        read -p "Enter Tunnel Port (e.g., 8443): " TUNNEL_PORT
        
        cat <<EOF > /etc/systemd/system/tunel-star-gost.service
[Unit]
Description=Tunel-Star Secure Server
After=network.target
[Service]
ExecStart=/usr/local/bin/gost -L relay+tls://:$TUNNEL_PORT
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}[Info] Listening securely on port $TUNNEL_PORT${NC}"

    else
        # Iran
        read -p "Enter FOREIGN Server IP: " REMOTE_IP
        analyze_ip "$REMOTE_IP" "FOREIGN"
        read -p "Enter FOREIGN Tunnel Port: " REMOTE_PORT
        read -p "Enter Local Port to Forward (e.g., 2082): " LOCAL_PORT
        
        cat <<EOF > /etc/systemd/system/tunel-star-gost.service
[Unit]
Description=Tunel-Star Secure Client
After=network.target
[Service]
ExecStart=/usr/local/bin/gost -L tcp://:$LOCAL_PORT/$REMOTE_IP:$LOCAL_PORT -L udp://:$LOCAL_PORT/$REMOTE_IP:$LOCAL_PORT -F relay+tls://$REMOTE_IP:$REMOTE_PORT
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}[Info] Traffic encrypted and sent to $REMOTE_IP${NC}"
    fi
    
    systemctl daemon-reload
    systemctl enable --now tunel-star-gost
    echo -e "${GREEN}[Success] Secure Tunnel Established!${NC}"
}

# =========================================================
#                 MODULE 4: VXLAN
# =========================================================
install_vxlan() {
    echo -e "${YELLOW}>> VXLAN Layer 2 Setup <<${NC}"
    read -p "Enter REMOTE Server IP: " REMOTE_IP
    analyze_ip "$REMOTE_IP" "UNKNOWN"
    
    read -p "Tunnel Internal IP (e.g., 192.168.100.1): " VXLAN_IP
    read -p "Enter VXLAN Port (Default 4789, Press Enter to skip): " VXLAN_PORT
    VXLAN_PORT=${VXLAN_PORT:-4789}
    
    INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    
    SERVICE_FILE="/etc/systemd/system/tunel-star-vxlan.service"
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Tunel-Star VXLAN Service
After=network.target
[Service]
ExecStartPre=/sbin/ip link add vxlan100 type vxlan id 100 remote $REMOTE_IP local $(hostname -I | awk '{print $1}') dev $INTERFACE dstport $VXLAN_PORT
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
    iptables -I INPUT -p udp --dport $VXLAN_PORT -j ACCEPT
    
    echo -e "${GREEN}[Success] VXLAN Service Installed on port $VXLAN_PORT.${NC}"
}

# =========================================================
#                 MODULE 5: BBR
# =========================================================
install_bbr() {
    echo -e "${BLUE}[Wait] Enabling Google BBR...${NC}"
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${GREEN}[Success] BBR Enabled.${NC}"
}

# =========================================================
#                 UNINSTALL
# =========================================================
uninstall_all() {
    echo -e "${RED}[!] Removing all configurations...${NC}"
    
    # Remove all services
    services=("tunel-star-ipv6" "tunel-star-vxlan" "tunel-star-gost" "haproxy")
    
    for svc in "${services[@]}"; do
        systemctl stop $svc > /dev/null 2>&1
        systemctl disable $svc > /dev/null 2>&1
        rm -f /etc/systemd/system/$svc.service
    done
    
    # Clean files
    rm -f /etc/haproxy/haproxy.cfg
    rm -f /etc/netplan/tunel-star-6to4.yaml
    rm -f /root/tunel-star-keepalive.sh
    rm -f /usr/local/bin/gost
    
    systemctl daemon-reload
    netplan apply > /dev/null 2>&1
    apt-get purge -y haproxy > /dev/null 2>&1
    
    echo -e "${GREEN}[Done] All Tunel-Star components removed.${NC}"
}

# =========================================================
#                 MAIN MENU
# =========================================================

install_deps
show_header

echo -e "Welcome to ${YELLOW}Tunel-Star${NC}. I will manage everything for you."
echo -e "Automatic IP detection and dependency installation is active.\n"

echo "Select Tunnel Type:"
echo "1) HAProxy (Simple TCP Tunnel)"
echo "2) IPv6 Tunnel (6to4 Bypass)"
echo "3) Secure Tunnel (GOST + TLS) [Anti-Filter]"
echo "4) VXLAN Tunnel (Layer 2 Gaming)"
echo "------------------------------------"
echo "5) Enable Google BBR"
echo "6) Uninstall Everything"
echo "7) Help / Advisor"
echo "0) Exit"
echo "------------------------------------"
read -p "Your Choice: " choice

case $choice in
    1) install_haproxy ;;
    2) install_ipv6 ;;
    3) install_secure_tunnel ;;
    4) install_vxlan ;;
    5) install_bbr ;;
    6) uninstall_all ;;
    7) show_advice; read -p "Press Enter...";;
    0) exit 0 ;;
    *) echo "Invalid option!" ;;
esac

echo -e "\n${CYAN}Task Completed. Thank you!${NC}"
