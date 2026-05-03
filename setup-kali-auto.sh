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
# Step 1: Prepare the disk image
# ──────────────────────────────────────────────────────────
echo "📦 Step 1/5: Preparing disk image..."
echo ""

# Check if libguestfs-tools is installed
if ! command -v virt-customize &>/dev/null; then
    echo "   📦 Installing libguestfs-tools..."
    apt install -y -qq libguestfs-tools
fi

# Customize the disk before creating VM
echo "   🔧 Setting up SSH and password..."
virt-customize -a "$QCOW2_PATH" \
    --password "kali:password:kali" \
    --run-command "systemctl enable ssh" \
    --install qemu-guest-agent \
    --run-command "systemctl enable qemu-guest-agent" \
    --selinux-relabel 2>&1 | grep -v "^libguestfs: trace:" || true

echo ""
echo "   ✅ Disk preparation complete"
echo ""

# ──────────────────────────────────────────────────────────
# Step 2: Create the VM
# ──────────────────────────────────────────────────────────
echo "📦 Step 2/5: Creating VM..."
echo ""

bash create-vm.sh "$QCOW2_PATH"

echo ""
echo "   ✅ VM created successfully"
echo ""

# Add serial console for better access
echo "   🖥️  Adding serial console..."
if ! virsh dumpxml "$VM_NAME" | grep -q '<console type='; then
    virt-xml "$VM_NAME" --add-device --console pty,target.type=serial 2>/dev/null || true
fi
echo ""

# ──────────────────────────────────────────────────────────
# Step 3: Wait for VM to boot and get IP
# ──────────────────────────────────────────────────────────
echo "⏳ Step 3/5: Waiting for VM to boot and acquire IP..."

VM_MAC=$(virsh domiflist "$VM_NAME" | grep br0 | awk '{print $5}')
KALI_IP=""

for i in $(seq 1 24); do
    sleep 5
    
    # Try multiple methods to find IP
    KALI_IP=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
    
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(arp-scan --interface=br0 --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
    fi
    
    # Also try virsh with agent (qemu-guest-agent should be running)
    if [[ -z "$KALI_IP" ]]; then
        KALI_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1 || true)
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
# Step 4: Wait for SSH and inject post-setup script
# ──────────────────────────────────────────────────────────
echo ""
echo "🔑 Step 4/5: Waiting for SSH and running post-setup..."
echo ""

# Install sshpass if needed
if ! command -v sshpass &>/dev/null; then
    echo "   📦 Installing sshpass..."
    apt install -y -qq sshpass
fi

# Wait for SSH
echo "   ⏳ Waiting for SSH to be available..."
SSH_READY=false
for i in $(seq 1 30); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        -o UserKnownHostsFile=/dev/null "$SSH_USER@$KALI_IP" "echo 'SSH ready'" &>/dev/null 2>&1; then
        echo "   ✅ SSH is ready"
        SSH_READY=true
        break
    fi
    sleep 2
done

# Kali's first-boot initialization can undo pre-boot virt-customize changes (SSH enable,
# host key generation). Re-apply fixes post-first-boot and retry, matching fix-kali-access.sh.
if [[ "$SSH_READY" = false ]]; then
    echo "   ⚠️  SSH not available — Kali first-boot likely reset SSH config."
    echo "   🔧 Applying post-first-boot SSH fix..."

    DISK_PATH=$(virsh domblklist "$VM_NAME" | grep -E '\.qcow2|\.img' | awk '{print $2}')

    echo "   🛑 Stopping VM..."
    virsh shutdown "$VM_NAME" || true
    for i in $(seq 1 30); do
        if ! virsh list --state-running | grep -q "$VM_NAME"; then break; fi
        sleep 1
    done
    if virsh list --state-running | grep -q "$VM_NAME"; then
        virsh destroy "$VM_NAME"
        sleep 2
    fi

    echo "   🔧 Re-customizing disk after first boot..."
    virt-customize -a "$DISK_PATH" \
        --password "kali:password:kali" \
        --run-command "systemctl enable ssh" \
        --run-command "systemctl enable qemu-guest-agent" \
        --selinux-relabel 2>&1 | grep -v "^libguestfs: trace:" || true

    echo "   🚀 Restarting VM..."
    virsh start "$VM_NAME"

    echo "   ⏳ Waiting for IP after restart..."
    KALI_IP=""
    for i in $(seq 1 24); do
        sleep 5
        KALI_IP=$(ip neigh show | grep -i "$VM_MAC" | grep -oP '(\d+\.){3}\d+' | head -1 || true)
        if [[ -z "$KALI_IP" ]]; then
            KALI_IP=$(arp-scan --interface=br0 --localnet 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' || true)
        fi
        if [[ -z "$KALI_IP" ]]; then
            KALI_IP=$(virsh domifaddr "$VM_NAME" --source agent 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1 || true)
        fi
        if [[ -n "$KALI_IP" ]]; then
            echo "   ✅ IP: $KALI_IP"
            break
        fi
    done

    if [[ -z "$KALI_IP" ]]; then
        echo "❌ Could not detect IP after fix attempt"
        exit 1
    fi

    echo "   ⏳ Waiting for SSH after fix..."
    for i in $(seq 1 30); do
        if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
            -o UserKnownHostsFile=/dev/null "$SSH_USER@$KALI_IP" "echo 'SSH ready'" &>/dev/null 2>&1; then
            echo "   ✅ SSH is ready"
            SSH_READY=true
            break
        fi
        sleep 2
    done

    if [[ "$SSH_READY" = false ]]; then
        echo "❌ SSH still not available after fix attempt"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Try: ssh kali@${KALI_IP}"
        echo "  2. Try: sudo virsh console $VM_NAME"
        echo "  3. Check: sudo virsh domifaddr $VM_NAME"
        exit 1
    fi
fi

# Copy and execute post-setup script
echo "   📤 Copying configuration script to VM..."
sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    configure-kali.sh "$SSH_USER@$KALI_IP:~/"

echo "   🚀 Executing configuration script (this may take 5-10 minutes)..."
echo ""

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t \
    "$SSH_USER@$KALI_IP" \
    "chmod +x ~/configure-kali.sh && echo '$SSH_PASS' | sudo -S ~/configure-kali.sh" || true

echo ""
echo "   ✅ Post-setup complete"

# ──────────────────────────────────────────────────────────
# Step 5: Reboot VM
# ──────────────────────────────────────────────────────────
echo ""
echo "🔄 Step 5/5: Rebooting VM to apply changes..."

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$KALI_IP" "echo '$SSH_PASS' | sudo -S reboot" || true

echo "   ✅ Reboot initiated"

# Wait for VM to go down
sleep 5

# Wait for VM to come back up
echo "   ⏳ Waiting for VM to come back online..."
for i in $(seq 1 30); do
    if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        -o UserKnownHostsFile=/dev/null "$SSH_USER@$KALI_IP" "echo 'VM ready'" &>/dev/null 2>&1; then
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
echo "    Console:    sudo virsh console $VM_NAME (Ctrl+] to exit)"
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
