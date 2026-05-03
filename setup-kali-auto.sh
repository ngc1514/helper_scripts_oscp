#!/usr/bin/env bash
#
# setup-kali-auto.sh
# Complete end-to-end Kali VM setup for headless operation
#
# Usage:
#   sudo ./setup-kali-auto.sh /path/to/kali.qcow2
#
# What it does:
#   1. Runs setup-kali-vm.sh to create the VM
#   2. Waits for VM to boot and SSH to be available
#   3. Automatically runs kali-post-setup.sh inside the VM
#   4. Reboots the VM to apply all changes
#
# This is perfect for headless servers where you want everything
# configured without needing GUI access.

set -euo pipefail

QCOW2_PATH="${1:-}"
VM_NAME="kali"
SSH_USER="kali"
SSH_PASS="kali"

# ──────────────────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "❌ Run this script with sudo."
    exit 1
fi

if [[ -z "$QCOW2_PATH" ]]; then
    echo "Usage: sudo $0 /path/to/kali.qcow2"
    exit 1
fi

if [[ ! -f "$QCOW2_PATH" ]]; then
    echo "❌ File not found: $QCOW2_PATH"
    exit 1
fi

if [[ ! -f "create-vm.sh" ]]; then
    echo "❌ create-vm.sh not found in current directory"
    exit 1
fi

if [[ ! -f "configure-kali.sh" ]]; then
    echo "❌ configure-kali.sh not found in current directory"
    exit 1
fi

echo "============================================"
echo "  Complete Kali VM Setup (Headless)"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────────────
# Step 1: Create the VM
# ──────────────────────────────────────────────────────────
echo "📦 Step 1/4: Creating VM..."
echo ""

bash create-vm.sh "$QCOW2_PATH"

echo ""
echo "   ✅ VM created successfully"
echo ""

# ──────────────────────────────────────────────────────────
# Step 2: Wait for VM to boot and get IP
# ──────────────────────────────────────────────────────────
echo "⏳ Step 2/4: Waiting for VM to boot and acquire IP..."

VM_MAC=$(virsh domiflist "$VM_NAME" | grep br0 | awk '{print $5}')
KALI_IP=""

for i in $(seq 1 24); do
    sleep 5
    
    # Try multiple methods to find IP
    KALI_IP=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(arp-scan --interface=br0 --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
    fi
    
    if [[ -n "$KALI_IP" ]]; then
        echo "   ✅ Kali IP: $KALI_IP"
        break
    fi
    
    if [[ $i -eq 24 ]]; then
        echo "❌ Could not detect Kali IP after 2 minutes"
        echo "   Try manually: sudo virsh domifaddr $VM_NAME"
        exit 1
    fi
done

# ──────────────────────────────────────────────────────────
# Step 3: Wait for SSH and inject post-setup script
# ──────────────────────────────────────────────────────────
echo ""
echo "🔑 Step 3/4: Waiting for SSH and running post-setup..."
echo ""

# Install sshpass if needed
if ! command -v sshpass &>/dev/null; then
    echo "   📦 Installing sshpass..."
    apt install -y -qq sshpass
fi

# Wait for SSH
echo "   ⏳ Waiting for SSH to be available..."
for i in $(seq 1 30); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        "$SSH_USER@$KALI_IP" "echo 'SSH ready'" &>/dev/null 2>&1; then
        echo "   ✅ SSH is ready"
        break
    fi
    
    if [[ $i -eq 30 ]]; then
        echo "❌ SSH not available after 60 seconds"
        exit 1
    fi
    
    sleep 2
done

# Copy and execute post-setup script
echo "   📤 Copying configuration script to VM..."
sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
    configure-kali.sh "$SSH_USER@$KALI_IP:~/"

echo "   🚀 Executing configuration script (this may take 5-10 minutes)..."
echo ""

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -t \
    "$SSH_USER@$KALI_IP" \
    "chmod +x ~/configure-kali.sh && echo '$SSH_PASS' | sudo -S ~/configure-kali.sh" || true

echo ""
echo "   ✅ Post-setup complete"

# ──────────────────────────────────────────────────────────
# Step 4: Reboot VM
# ──────────────────────────────────────────────────────────
echo ""
echo "🔄 Step 4/4: Rebooting VM to apply changes..."

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
    "$SSH_USER@$KALI_IP" "echo '$SSH_PASS' | sudo -S reboot" || true

echo "   ✅ Reboot initiated"

# Wait for VM to go down
sleep 5

# Wait for VM to come back up
echo "   ⏳ Waiting for VM to come back online..."
for i in $(seq 1 30); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        "$SSH_USER@$KALI_IP" "echo 'VM ready'" &>/dev/null 2>&1; then
        echo "   ✅ VM is back online"
        break
    fi
    sleep 5
done

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ Complete Setup Finished!"
echo "============================================"
echo ""
echo "  Kali VM is ready at: $KALI_IP"
echo ""
echo "  Access methods:"
echo "    SSH:        ssh kali@${KALI_IP}"
echo "    NoMachine:  Connect to ${KALI_IP}:4000"
echo "                (Download client: https://www.nomachine.com/download)"
echo ""
echo "  Default credentials: kali / kali"
echo ""
echo "  Desktop:     GNOME with auto-login"
echo "  Installed:   Brave Browser, Sublime Text"
echo ""
echo "  VM Management:"
echo "    sudo virsh list --all"
echo "    sudo virsh shutdown $VM_NAME"
echo "    sudo virsh start $VM_NAME"
echo ""
