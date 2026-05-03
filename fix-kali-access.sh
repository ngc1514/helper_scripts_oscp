#!/usr/bin/env bash
#
# fix-kali-access.sh
# Fixes SSH and console access issues with Kali VM
#
# Usage:
#   sudo ./fix-kali-access.sh
#
# What it does:
#   1. Shuts down the VM safely
#   2. Uses virt-customize to:
#      - Reset kali user password to 'kali'
#      - Enable SSH server
#      - Install and enable qemu-guest-agent
#   3. Adds serial console to VM definition
#   4. Restarts the VM
#   5. Waits for SSH to become available

set -euo pipefail

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

# Check if libguestfs-tools is installed
if ! command -v virt-customize &>/dev/null; then
    echo "📦 Installing libguestfs-tools..."
    apt update -qq
    apt install -y libguestfs-tools
fi

echo "============================================"
echo "  Fixing Kali VM Access"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────────────
# Step 1: Get VM disk path
# ──────────────────────────────────────────────────────────
echo "🔍 Finding VM disk..."

if ! virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "❌ VM '$VM_NAME' does not exist"
    exit 1
fi

DISK_PATH=$(virsh domblklist "$VM_NAME" | grep -E '\.qcow2|\.img' | awk '{print $2}')

if [[ -z "$DISK_PATH" ]]; then
    echo "❌ Could not find disk for VM '$VM_NAME'"
    exit 1
fi

echo "   ✅ Found disk: $DISK_PATH"

# ──────────────────────────────────────────────────────────
# Step 2: Shutdown VM if running
# ──────────────────────────────────────────────────────────
if virsh list --state-running | grep -q "$VM_NAME"; then
    echo "🛑 Shutting down VM..."
    virsh shutdown "$VM_NAME"
    
    # Wait for shutdown (max 30 seconds)
    for i in $(seq 1 30); do
        if ! virsh list --state-running | grep -q "$VM_NAME"; then
            break
        fi
        sleep 1
    done
    
    # Force destroy if still running
    if virsh list --state-running | grep -q "$VM_NAME"; then
        echo "   ⚠️  Forcing shutdown..."
        virsh destroy "$VM_NAME"
        sleep 2
    fi
    
    echo "   ✅ VM stopped"
else
    echo "ℹ️  VM is already stopped"
fi

# ──────────────────────────────────────────────────────────
# Step 3: Customize the disk image
# ──────────────────────────────────────────────────────────
echo "🔧 Customizing VM disk (this may take a minute)..."
echo ""

# Use virt-customize to:
# 1. Set kali user password
# 2. Enable SSH
# 3. Install qemu-guest-agent for better VM integration
virt-customize -a "$DISK_PATH" \
    --password "kali:password:kali" \
    --run-command "systemctl enable ssh" \
    --install qemu-guest-agent \
    --run-command "systemctl enable qemu-guest-agent" \
    --selinux-relabel 2>&1 | grep -v "^libguestfs: trace:" || true

echo ""
echo "   ✅ Disk customization complete"

# ──────────────────────────────────────────────────────────
# Step 4: Add serial console to VM
# ──────────────────────────────────────────────────────────
echo "🖥️  Adding serial console..."

# Check if serial console already exists
if virsh dumpxml "$VM_NAME" | grep -q '<console type='; then
    echo "   ℹ️  Serial console already configured"
else
    # Add serial console
    virt-xml "$VM_NAME" --add-device --console pty,target.type=serial
    echo "   ✅ Serial console added"
fi

# ──────────────────────────────────────────────────────────
# Step 5: Start VM
# ──────────────────────────────────────────────────────────
echo "🚀 Starting VM..."
virsh start "$VM_NAME"
echo "   ✅ VM started"

# ──────────────────────────────────────────────────────────
# Step 6: Wait for network and SSH
# ──────────────────────────────────────────────────────────
echo ""
echo "⏳ Waiting for VM to boot and get IP address..."

# Get MAC address
VM_MAC=$(virsh domiflist "$VM_NAME" | grep br0 | awk '{print $5}')

if [[ -z "$VM_MAC" ]]; then
    echo "❌ Could not get VM MAC address"
    exit 1
fi

echo "   MAC: $VM_MAC"

# Wait for IP (up to 2 minutes)
KALI_IP=""
for i in $(seq 1 24); do
    sleep 5
    
    # Try multiple methods to find IP
    KALI_IP=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(arp-scan --interface=br0 --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
    fi
    
    # Also try virsh with agent (might work now with qemu-guest-agent)
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    fi
    
    if [[ -n "$KALI_IP" ]]; then
        echo "   ✅ IP found: $KALI_IP"
        break
    fi
    
    if [[ $i -eq 24 ]]; then
        echo "❌ Could not detect IP after 2 minutes"
        echo ""
        echo "Try manually:"
        echo "  sudo arp-scan --interface=br0 --localnet | grep -i $VM_MAC"
        echo "  sudo virsh console $VM_NAME"
        exit 1
    fi
    
    echo -n "."
done

echo ""
echo "🔑 Waiting for SSH to be available..."

# Install sshpass if needed
if ! command -v sshpass &>/dev/null; then
    echo "   📦 Installing sshpass..."
    apt install -y -qq sshpass
fi

# Wait for SSH (up to 2 minutes)
SSH_READY=false
for i in $(seq 1 24); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        -o UserKnownHostsFile=/dev/null "$SSH_USER@$KALI_IP" "echo 'SSH ready'" &>/dev/null 2>&1; then
        SSH_READY=true
        echo "   ✅ SSH is ready!"
        break
    fi
    
    sleep 5
    echo -n "."
done

echo ""

if [[ "$SSH_READY" = false ]]; then
    echo "⚠️  SSH not responding yet. This could mean:"
    echo "   1. SSH service is still starting (wait a bit longer)"
    echo "   2. Firewall is blocking port 22"
    echo "   3. Network configuration issue"
    echo ""
    echo "Try manually:"
    echo "   ssh kali@${KALI_IP}"
    echo "   sudo virsh console $VM_NAME"
    exit 1
fi

# ──────────────────────────────────────────────────────────
# Step 7: Test SSH connection
# ──────────────────────────────────────────────────────────
echo "🧪 Testing SSH connection..."

SSH_OUTPUT=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null "$SSH_USER@$KALI_IP" \
    "hostname && whoami && systemctl is-active ssh" 2>/dev/null || echo "FAILED")

if [[ "$SSH_OUTPUT" == "FAILED" ]]; then
    echo "❌ SSH test failed"
    exit 1
fi

echo "   ✅ SSH connection successful!"
echo ""
echo "   Output:"
echo "$SSH_OUTPUT" | sed 's/^/      /'

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ Kali VM Access Fixed!"
echo "============================================"
echo ""
echo "  IP Address:  $KALI_IP"
echo "  Username:    kali"
echo "  Password:    kali"
echo ""
echo "  Access methods:"
echo "    SSH:            ssh kali@${KALI_IP}"
echo "    Serial Console: sudo virsh console $VM_NAME"
echo "                    (Press Enter after connecting)"
echo "                    (Ctrl+] to exit)"
echo ""
echo "  VM Management:"
echo "    sudo virsh list --all"
echo "    sudo virsh shutdown $VM_NAME"
echo "    sudo virsh start $VM_NAME"
echo "    sudo virsh console $VM_NAME"
echo ""
echo "  Next steps:"
echo "    1. SSH into the VM: ssh kali@${KALI_IP}"
echo "    2. Run configure-kali.sh to set up desktop environment"
echo "    3. Or use configure-vm-remote.sh to do it automatically"
echo ""
