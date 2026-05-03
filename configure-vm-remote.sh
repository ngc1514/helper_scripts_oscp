#!/usr/bin/env bash
#
# configure-vm-remote.sh
# Injects configure-kali.sh into a running Kali VM and executes it via SSH
#
# Usage:
#   ./configure-vm-remote.sh [kali-ip] [--desktop xfce|gnome]
#
# If no IP is provided, attempts to auto-detect from virsh/arp-scan.
# --desktop is forwarded to configure-kali.sh (defaults to xfce).

set -euo pipefail

VM_NAME="kali"
SCRIPT_NAME="configure-kali.sh"
SSH_USER="kali"
SSH_PASS="kali"

DESKTOP="xfce"
KALI_IP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --desktop)
            DESKTOP="${2:-}"
            shift 2
            ;;
        --desktop=*)
            DESKTOP="${1#--desktop=}"
            shift
            ;;
        -h|--help)
            sed -n '2,11p' "$0"
            exit 0
            ;;
        -*)
            echo "❌ Unknown flag: $1"
            exit 1
            ;;
        *)
            if [[ -z "$KALI_IP" ]]; then
                KALI_IP="$1"
            else
                echo "❌ Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

case "$DESKTOP" in
    xfce|gnome) ;;
    *)
        echo "❌ Invalid --desktop value: '$DESKTOP' (expected: xfce, gnome)"
        exit 1
        ;;
esac

if [[ -z "$KALI_IP" ]]; then
    echo "🔍 Auto-detecting Kali VM IP..."
    
    # Method 1: Try virsh domifaddr
    KALI_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    
    # Method 2: Try ARP cache
    if [[ -z "$KALI_IP" ]]; then
        VM_MAC=$(sudo virsh domiflist "$VM_NAME" | grep br0 | awk '{print $5}')
        KALI_IP=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    fi
    
    # Method 3: Try arp-scan
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(sudo arp-scan --interface=br0 --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
    fi
    
    if [[ -z "$KALI_IP" ]]; then
        echo "❌ Could not detect Kali IP. Please provide it manually:"
        echo "   $0 <kali-ip>"
        exit 1
    fi
    
    echo "   ✅ Found Kali at: $KALI_IP"
fi

# ──────────────────────────────────────────────────────────
# Check if script exists
# ──────────────────────────────────────────────────────────
if [[ ! -f "$SCRIPT_NAME" ]]; then
    echo "❌ $SCRIPT_NAME not found in current directory"
    exit 1
fi

echo "============================================"
echo "  Injecting Configuration Script into Kali VM"
echo "  Target: $SSH_USER@$KALI_IP"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────────────
# Install sshpass if needed (for password-based SCP)
# ──────────────────────────────────────────────────────────
if ! command -v sshpass &>/dev/null; then
    echo "📦 Installing sshpass..."
    sudo apt install -y sshpass
fi

# ──────────────────────────────────────────────────────────
# Wait for SSH to be available
# ──────────────────────────────────────────────────────────
echo "⏳ Waiting for SSH to be available..."
for i in $(seq 1 30); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        "$SSH_USER@$KALI_IP" "echo 'SSH ready'" &>/dev/null; then
        echo "   ✅ SSH is ready"
        break
    fi
    
    if [[ $i -eq 30 ]]; then
        echo "❌ SSH not available after 60 seconds. Is the VM running?"
        echo "   Check: sudo virsh list --all"
        exit 1
    fi
    
    sleep 2
done

# ──────────────────────────────────────────────────────────
# Copy script to VM
# ──────────────────────────────────────────────────────────
echo "📤 Copying $SCRIPT_NAME to VM..."
sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
    "$SCRIPT_NAME" "$SSH_USER@$KALI_IP:~/"

echo "   ✅ Script copied"

# ──────────────────────────────────────────────────────────
# Execute script on VM
# ──────────────────────────────────────────────────────────
echo ""
echo "🚀 Executing configuration script on VM..."
echo "   (This may take several minutes...)"
echo ""

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -t \
    "$SSH_USER@$KALI_IP" \
    "chmod +x ~/$SCRIPT_NAME && echo '$SSH_PASS' | sudo -S ~/$SCRIPT_NAME --desktop $DESKTOP"

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ Configuration complete!"
echo "============================================"
echo ""
echo "  The VM will reboot to apply changes."
echo "  After reboot, connect via NoMachine:"
echo "    - Download NoMachine client: https://www.nomachine.com/download"
echo "    - Connect to: $KALI_IP:4000"
echo "    - Login: $SSH_USER / $SSH_PASS"
echo ""
