#!/usr/bin/env bash
#
# setup-kali-vm.sh
# Sets up a bridged QEMU/KVM Kali Linux VM with autostart.
#
# Usage:
#   sudo ./setup-kali-vm.sh /path/to/kali.qcow2 [--graphics virtio|qxl]
#
# What it does:
#   1. Installs QEMU/KVM + libvirt
#   2. Creates a br0 bridge on eno1 (netplan + NetworkManager)
#   3. Imports the Kali qcow2 as a VM on the bridge (SPICE)
#   4. Enables autostart so the VM launches on boot
#
# Graphics modes:
#   virtio (default) — virtio-gpu + virgl, SPICE local-only with GL passthrough.
#                      Faster guest rendering → smoother NoMachine sessions and
#                      buttery local virt-manager. Breaks GNOME's compositor.
#   qxl              — plain QXL with network-listening SPICE. Slower (software
#                      GL in the guest) but broadly compatible. Use this if you
#                      run GNOME or need remote SPICE.
#
# Prerequisites:
#   - Ubuntu with netplan + NetworkManager
#   - Wired interface named eno1
#   - A pre-built Kali QEMU qcow2 image
#
# ⚠️  WARNING: This will briefly drop your wired network connection
#     while the bridge is created. Have a fallback (WiFi, console).

set -euo pipefail

# ──────────────────────────────────────────────────────────
# Configuration — edit these to taste
# ──────────────────────────────────────────────────────────
VM_NAME="kali"
VM_RAM=8192         # MB
VM_CPUS=8
BRIDGE_NAME="br0"
PHYS_IFACE="eno1"   # your wired NIC
OS_VARIANT="debian12"
GRAPHICS="virtio"   # virtio | qxl
QCOW2_PATH=""

# ──────────────────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --graphics)
            GRAPHICS="${2:-}"
            shift 2
            ;;
        --graphics=*)
            GRAPHICS="${1#--graphics=}"
            shift
            ;;
        -h|--help)
            sed -n '2,28p' "$0"
            exit 0
            ;;
        -*)
            echo "❌ Unknown flag: $1"
            echo "Usage: sudo $0 /path/to/kali.qcow2 [--graphics virtio|qxl]"
            exit 1
            ;;
        *)
            if [[ -z "$QCOW2_PATH" ]]; then
                QCOW2_PATH="$1"
            else
                echo "❌ Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

case "$GRAPHICS" in
    virtio|qxl) ;;
    *)
        echo "❌ Invalid --graphics value: '$GRAPHICS' (expected: virtio, qxl)"
        exit 1
        ;;
esac

# ──────────────────────────────────────────────────────────
# Preflight checks
# ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "❌ Run this script with sudo."
    exit 1
fi

if [[ -z "$QCOW2_PATH" ]]; then
    echo "Usage: sudo $0 /path/to/kali.qcow2 [--graphics virtio|qxl]"
    exit 1
fi

if [[ ! -f "$QCOW2_PATH" ]]; then
    echo "❌ File not found: $QCOW2_PATH"
    exit 1
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "❌ VM '$VM_NAME' already exists. To recreate:"
    echo "   sudo virsh destroy $VM_NAME   # if running"
    echo "   sudo virsh undefine $VM_NAME"
    exit 1
fi

echo "============================================"
echo "  Kali VM Setup"
echo "  Image:    $QCOW2_PATH"
echo "  VM:       $VM_NAME ($VM_CPUS vCPUs, ${VM_RAM}MB RAM)"
echo "  Bridge:   $BRIDGE_NAME on $PHYS_IFACE"
echo "  Graphics: $GRAPHICS"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────────────
# Step 1: Install packages
# ──────────────────────────────────────────────────────────
echo "📦 Installing QEMU/KVM and libvirt..."
apt update -qq
apt install -y -qq qemu-kvm libvirt-daemon-system libvirt-clients \
    bridge-utils virtinst arp-scan > /dev/null

# Add the invoking user to libvirt/kvm groups
REAL_USER="${SUDO_USER:-$USER}"
usermod -aG libvirt,kvm "$REAL_USER" 2>/dev/null || true

echo "   ✅ Packages installed"

# ──────────────────────────────────────────────────────────
# Step 2: Create bridge network (netplan)
# ──────────────────────────────────────────────────────────
NETPLAN_FILE="/etc/netplan/02-bridge.yaml"

if ip link show "$BRIDGE_NAME" &>/dev/null; then
    echo "🌐 Bridge $BRIDGE_NAME already exists, skipping netplan setup."
else
    echo "🌐 Creating bridge $BRIDGE_NAME on $PHYS_IFACE..."

    cat > "$NETPLAN_FILE" << YAML
network:
  version: 2
  renderer: NetworkManager

  ethernets:
    ${PHYS_IFACE}:
      dhcp4: false
      dhcp6: false

  bridges:
    ${BRIDGE_NAME}:
      interfaces: [${PHYS_IFACE}]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
YAML

    chmod 600 "$NETPLAN_FILE"

    echo "   ⚠️  Applying netplan — network will blip..."
    netplan apply
    sleep 5

    echo "   ✅ Bridge created"
fi

# ──────────────────────────────────────────────────────────
# Step 2.5: Configure NetworkManager for headless operation
# ──────────────────────────────────────────────────────────
echo "🔧 Configuring NetworkManager for headless operation..."

# Remove user-specific permissions and enable autoconnect for bridge and physical interface
# This allows connections to start at boot without requiring user login
for conn in "netplan-${BRIDGE_NAME}" "netplan-${PHYS_IFACE}"; do
    if nmcli connection show "$conn" &>/dev/null; then
        nmcli connection modify "$conn" connection.permissions "" 2>/dev/null || true
        nmcli connection modify "$conn" connection.autoconnect yes 2>/dev/null || true
        echo "   ✅ Configured $conn for autoconnect"
    fi
done

echo "   ✅ Headless networking configured"

# ──────────────────────────────────────────────────────────
# Step 3: Allow QEMU to use the bridge
# ──────────────────────────────────────────────────────────
mkdir -p /etc/qemu
if ! grep -q "allow $BRIDGE_NAME" /etc/qemu/bridge.conf 2>/dev/null; then
    echo "allow $BRIDGE_NAME" >> /etc/qemu/bridge.conf
fi

# ──────────────────────────────────────────────────────────
# Step 4: Import the Kali VM
# ──────────────────────────────────────────────────────────
echo "🖥️  Creating VM '$VM_NAME' (graphics: $GRAPHICS)..."

# Resolve graphics mode → virt-install --graphics / --video flags.
# virtio path enables virgl: the guest gets a real GPU pipeline through to the
# host, so anything OpenGL (compositors, GTK, browsers, terminals) renders at
# GPU speed — and NoMachine captures the smooth result. Requires listen=none
# because GL frame passthrough is local-only (DMA-BUF).
if [[ "$GRAPHICS" == "virtio" ]]; then
    # listens0.* is array notation for the <listen> sub-element; listen.type is
    # not a valid virt-install key. accel3d lives at model.acceleration.accel3d.
    GRAPHICS_OPT="spice,listens0.type=none,gl.enable=yes,image.compression=off"
    VIDEO_OPT="model.type=virtio,model.acceleration.accel3d=on"
else
    GRAPHICS_OPT="spice,listen=0.0.0.0"
    VIDEO_OPT="model.type=qxl"
fi

virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --vcpus "$VM_CPUS" \
    --disk "path=${QCOW2_PATH},format=qcow2" \
    --import \
    --os-variant "$OS_VARIANT" \
    --network "bridge=${BRIDGE_NAME},model=virtio" \
    --graphics "$GRAPHICS_OPT" \
    --video "$VIDEO_OPT" \
    --channel spicevmc,target.type=virtio,target.name=com.redhat.spice.0 \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --noautoconsole

echo "   ✅ VM created and running"

# ──────────────────────────────────────────────────────────
# Step 5: Enable autostart
# ──────────────────────────────────────────────────────────
virsh autostart "$VM_NAME"
echo "   ✅ Autostart enabled"

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ All done!"
echo "============================================"
echo ""
echo "  VM status:"
virsh list --all | grep "$VM_NAME"
echo ""
echo "  Waiting for Kali to get an IP (up to 60s)..."

# Get the VM's MAC address
VM_MAC=$(virsh domiflist "$VM_NAME" | grep "$BRIDGE_NAME" | awk '{print $5}')

IP_FOUND=""
for i in $(seq 1 12); do
    sleep 5
    # Try multiple methods since bridged networks don't report to libvirt
    # Method 1: Check ARP cache
    IP_FOUND=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    
    # Method 2: Use arp-scan if Method 1 fails
    if [[ -z "$IP_FOUND" ]]; then
        IP_FOUND=$(arp-scan --interface="$BRIDGE_NAME" --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
    fi
    
    if [[ -n "$IP_FOUND" ]]; then
        break
    fi
done

if [[ -n "$IP_FOUND" ]]; then
    echo ""
    echo "  🎯 Kali IP: $IP_FOUND"
    echo ""
    echo "  Connect from your Mac:"
    echo "    SSH:  ssh kali@${IP_FOUND}"
    echo "    RDP:  open Microsoft Remote Desktop → ${IP_FOUND}"
    echo "  Local: open virt-manager (SPICE — clipboard + auto-resize work)"
else
    echo ""
    echo "  ⏳ Kali hasn't grabbed an IP yet. Check manually:"
    echo "    sudo virsh domifaddr $VM_NAME"
    echo "    sudo arp-scan --interface=$BRIDGE_NAME 10.0.0.0/24"
fi

echo ""
echo "  Default creds: kali / kali"
echo "  Remember to enable SSH + xRDP inside Kali:"
echo "    sudo systemctl enable ssh --now"
echo "    sudo apt install -y xrdp && sudo systemctl enable xrdp --now"
echo ""
echo "  Useful commands:"
echo "    sudo virsh list --all        # list VMs"
echo "    sudo virsh start $VM_NAME    # start"
echo "    sudo virsh shutdown $VM_NAME # graceful shutdown"
echo "    sudo virsh dominfo $VM_NAME  # check autostart, state, etc."
echo ""
