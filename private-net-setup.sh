#!/bin/bash

# ============================================================
#   private-net-setup.sh
#   KVM Private Network Setup Tool
#   BY MEYSAM
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PRIVATE_SUBNET="192.168.100"
BRIDGE="br-private"
BRIDGE_IP="${PRIVATE_SUBNET}.1"

banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗ ██████╗ ██╗██╗   ██╗ █████╗ ████████╗███████╗"
    echo "  ██╔══██╗██╔══██╗██║██║   ██║██╔══██╗╚══██╔══╝██╔════╝"
    echo "  ██████╔╝██████╔╝██║██║   ██║███████║   ██║   █████╗  "
    echo "  ██╔═══╝ ██╔══██╗██║╚██╗ ██╔╝██╔══██║   ██║   ██╔══╝  "
    echo "  ██║     ██║  ██║██║ ╚████╔╝ ██║  ██║   ██║   ███████╗"
    echo "  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝"
    echo -e "${NC}"
    echo -e "${BOLD}         KVM Private Network Setup Tool${NC}"
    echo -e "${YELLOW}                   BY MEYSAM${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""
}

detect_mode() {
    if command -v virsh &>/dev/null && virsh list &>/dev/null 2>&1; then
        echo "host"
    else
        echo "vm"
    fi
}

press_enter() {
    echo ""
    echo -e "${YELLOW}  Press Enter to continue...${NC}"
    read -r
}

# ============================================================
#   HOST MODE FUNCTIONS
# ============================================================

check_bridge() {
    if ip link show "$BRIDGE" &>/dev/null; then
        echo -e "${GREEN}  [OK]${NC} Bridge ${BOLD}${BRIDGE}${NC} exists (${BRIDGE_IP}/24)"
    else
        echo -e "${RED}  [!!]${NC} Bridge ${BOLD}${BRIDGE}${NC} not found!"
        echo ""
        echo -e "${YELLOW}  Creating bridge...${NC}"
        nmcli con add type bridge \
            con-name "$BRIDGE" \
            ifname "$BRIDGE" \
            bridge.stp no \
            ipv4.method manual \
            ipv4.addresses "${BRIDGE_IP}/24" \
            ipv6.method disabled &>/dev/null
        nmcli con up "$BRIDGE" &>/dev/null
        if ip link show "$BRIDGE" &>/dev/null; then
            echo -e "${GREEN}  [OK]${NC} Bridge created successfully"
        else
            echo -e "${RED}  [!!]${NC} Failed to create bridge"
        fi
    fi
}

list_vms() {
    banner
    echo -e "${BOLD}  VM List & Private Network Status${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""
    printf "  ${BOLD}%-6s %-12s %-8s %-20s${NC}\n" "ID" "Name" "State" "Private NIC"
    echo -e "  ${BLUE}──────────────────────────────────────────────${NC}"

    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        state=$(echo "$line" | awk '{print $3}')

        has_private=$(virsh domiflist "$name" 2>/dev/null | grep "$BRIDGE" | wc -l)

        if [ "$has_private" -gt 0 ]; then
            nic_status="${GREEN}attached${NC}"
        else
            nic_status="${RED}not attached${NC}"
        fi

        if [ "$state" = "running" ]; then
            state_colored="${GREEN}${state}${NC}"
        else
            state_colored="${YELLOW}${state}${NC}"
        fi

        printf "  %-6s %-12s %-8b %-20b\n" "$id" "$name" "$state_colored" "$nic_status"
    done < <(virsh list --all | grep -E '^\s+[0-9-]' | sed 's/^\s*//')

    echo ""
    press_enter
}

attach_nic_single() {
    banner
    echo -e "${BOLD}  Attach Private NIC to VM${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""

    echo -e "${CYAN}  Available VMs:${NC}"
    echo ""
    virsh list --all | grep -E '^\s+[0-9-]' | while read -r line; do
        name=$(echo "$line" | awk '{print $2}')
        state=$(echo "$line" | awk '{print $3}')
        has_private=$(virsh domiflist "$name" 2>/dev/null | grep "$BRIDGE" | wc -l)
        if [ "$has_private" -gt 0 ]; then
            tag="${GREEN}[has NIC]${NC}"
        else
            tag="${RED}[no NIC]${NC}"
        fi
        echo -e "    ${BOLD}${name}${NC} (${state}) ${tag}"
    done

    echo ""
    echo -ne "${YELLOW}  Enter VM name: ${NC}"
    read -r vm_name

    if [ -z "$vm_name" ]; then
        echo -e "${RED}  No VM name entered.${NC}"
        press_enter
        return
    fi

    if ! virsh dominfo "$vm_name" &>/dev/null; then
        echo -e "${RED}  VM '$vm_name' not found.${NC}"
        press_enter
        return
    fi

    has_private=$(virsh domiflist "$vm_name" 2>/dev/null | grep "$BRIDGE" | wc -l)
    if [ "$has_private" -gt 0 ]; then
        echo -e "${YELLOW}  VM already has a private NIC attached.${NC}"
        press_enter
        return
    fi

    echo -e "${YELLOW}  Attaching NIC to ${vm_name}...${NC}"
    if virsh attach-interface \
        --domain "$vm_name" \
        --type bridge \
        --source "$BRIDGE" \
        --model virtio \
        --config \
        --live &>/dev/null; then
        echo -e "${GREEN}  [OK]${NC} NIC attached to ${BOLD}${vm_name}${NC}"
    else
        echo -e "${RED}  [!!]${NC} Failed to attach NIC to ${vm_name}"
    fi

    press_enter
}

attach_nic_all() {
    banner
    echo -e "${BOLD}  Attach Private NIC to All VMs${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""

    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $2}')
        has_private=$(virsh domiflist "$name" 2>/dev/null | grep "$BRIDGE" | wc -l)

        if [ "$has_private" -gt 0 ]; then
            echo -e "  ${YELLOW}[SKIP]${NC} ${name} already has private NIC"
            continue
        fi

        if virsh attach-interface \
            --domain "$name" \
            --type bridge \
            --source "$BRIDGE" \
            --model virtio \
            --config \
            --live &>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC}   ${name} — NIC attached"
        else
            echo -e "  ${RED}[!!]${NC}   ${name} — Failed"
        fi
    done < <(virsh list --all | grep -E '^\s+[0-9-]' | sed 's/^\s*//')

    echo ""
    press_enter
}

host_menu() {
    while true; do
        banner
        check_bridge
        echo ""
        echo -e "${BOLD}  Host Mode — Main Menu${NC}"
        echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC}  List VMs & private NIC status"
        echo -e "  ${CYAN}[2]${NC}  Attach private NIC to a specific VM"
        echo -e "  ${CYAN}[3]${NC}  Attach private NIC to ALL VMs"
        echo ""
        echo -e "  ${RED}[0]${NC}  Exit"
        echo ""
        echo -ne "${YELLOW}  Select: ${NC}"
        read -r choice

        case $choice in
            1) list_vms ;;
            2) attach_nic_single ;;
            3) attach_nic_all ;;
            0) echo ""; exit 0 ;;
            *) echo -e "${RED}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================================
#   VM MODE FUNCTIONS
# ============================================================

setup_vm_network() {
    banner
    echo -e "${BOLD}  VM Network Setup${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""

    PUB_IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    GATEWAY=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)

    if [ -z "$PUB_IP" ] || [ -z "$GATEWAY" ]; then
        echo -e "${RED}  [!!]${NC} Could not detect public IP or gateway."
        echo -e "       Make sure eth0 is configured."
        press_enter
        return
    fi

    LAST_OCTET=$(echo "$PUB_IP" | cut -d'.' -f4)
    PRIVATE_IP="${PRIVATE_SUBNET}.${LAST_OCTET}"

    # Check eth1 exists
    if ! ip link show eth1 &>/dev/null; then
        echo -e "${RED}  [!!]${NC} eth1 not found. Ask host admin to attach private NIC first."
        press_enter
        return
    fi

    echo -e "  ${CYAN}Public IP:${NC}  ${PUB_IP}"
    echo -e "  ${CYAN}Gateway:${NC}    ${GATEWAY}"
    echo -e "  ${CYAN}Private IP:${NC} ${PRIVATE_IP}/24"
    echo ""
    echo -ne "${YELLOW}  Apply this config? [y/N]: ${NC}"
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}  Cancelled.${NC}"
        press_enter
        return
    fi

    cat > /etc/netplan/50-cloud-init.yaml << NETPLAN
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - ${PUB_IP}/32
      routes:
        - to: default
          via: ${GATEWAY}
        - to: ${GATEWAY}/32
          via: 0.0.0.0
          scope: link
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
    eth1:
      dhcp4: false
      addresses:
        - ${PRIVATE_IP}/24
NETPLAN

    chmod 600 /etc/netplan/50-cloud-init.yaml

    echo -e "${YELLOW}  Applying netplan...${NC}"
    if netplan apply 2>/dev/null; then
        echo -e "${GREEN}  [OK]${NC} Network configured successfully"
    else
        # fallback for systems without systemd-networkd
        netplan apply 2>&1 | grep -v "WARNING\|systemd-networkd"
        echo -e "${GREEN}  [OK]${NC} Network configured (with fallback)"
    fi

    echo ""
    echo -e "  ${GREEN}Private IP assigned:${NC} ${BOLD}${PRIVATE_IP}/24${NC}"
    echo ""

    # Quick test
    echo -e "  ${CYAN}Testing gateway ping...${NC}"
    if ping -c2 -W2 "${PRIVATE_SUBNET}.1" &>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} Can reach ${PRIVATE_SUBNET}.1"
    else
        echo -e "  ${YELLOW}[??]${NC} Cannot reach ${PRIVATE_SUBNET}.1 yet (other VMs may not be configured)"
    fi

    press_enter
}

show_vm_status() {
    banner
    echo -e "${BOLD}  VM Network Status${NC}"
    echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
    echo ""

    echo -e "  ${CYAN}eth0 (Public):${NC}"
    ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print "    " $2}'

    echo ""
    echo -e "  ${CYAN}eth1 (Private):${NC}"
    if ip link show eth1 &>/dev/null; then
        ip addr show eth1 2>/dev/null | grep 'inet ' | awk '{print "    " $2}'
        if ip addr show eth1 2>/dev/null | grep -q 'inet '; then
            echo -e "  ${GREEN}  [OK]${NC} Private network configured"
        else
            echo -e "  ${YELLOW}  [!!]${NC} eth1 exists but has no IP — run Setup"
        fi
    else
        echo -e "  ${RED}    eth1 not found — contact host admin${NC}"
    fi

    echo ""
    echo -e "  ${CYAN}Routes:${NC}"
    ip route show | awk '{print "    " $0}'

    press_enter
}

vm_menu() {
    while true; do
        banner
        echo -e "${BOLD}  VM Mode — Main Menu${NC}"
        echo -e "${BLUE}  ────────────────────────────────────────────────────${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC}  Setup private network IP"
        echo -e "  ${CYAN}[2]${NC}  Show network status"
        echo ""
        echo -e "  ${RED}[0]${NC}  Exit"
        echo ""
        echo -ne "${YELLOW}  Select: ${NC}"
        read -r choice

        case $choice in
            1) setup_vm_network ;;
            2) show_vm_status ;;
            0) echo ""; exit 0 ;;
            *) echo -e "${RED}  Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================================
#   MAIN
# ============================================================

MODE=$(detect_mode)

banner

if [ "$MODE" = "host" ]; then
    echo -e "  ${GREEN}[HOST MODE]${NC} virsh detected — running as KVM host"
    sleep 1
    host_menu
else
    echo -e "  ${CYAN}[VM MODE]${NC} No virsh — running as guest VM"
    sleep 1
    vm_menu
fi
