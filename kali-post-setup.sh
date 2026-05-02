#!/usr/bin/env bash
#
# kali-post-setup.sh
# Run inside Kali after first boot.
#
# What it does:
#   1. Enables GDM3 auto-login (no password prompt on boot)
#   2. Enables SSH server on boot
#   3. Installs RustDesk for remote desktop access
#
# Usage:
#   chmod +x kali-post-setup.sh
#   sudo ./kali-post-setup.sh

set -euo pipefail

# ──────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────
AUTO_LOGIN_USER="kali"
RUSTDESK_VERSION="1.4.6"
RUSTDESK_DEB="rustdesk-${RUSTDESK_VERSION}-x86_64.deb"
RUSTDESK_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${RUSTDESK_DEB}"

# ──────────────────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "❌ Run this script with sudo."
    exit 1
fi

echo "============================================"
echo "  Kali Post-Install Setup"
echo "============================================"
echo ""

# ──────────────────────────────────────────────────────────
# 1. Enable GDM3 auto-login
# ──────────────────────────────────────────────────────────
echo "🔓 Enabling auto-login for '$AUTO_LOGIN_USER'..."

GDM_CONF="/etc/gdm3/daemon.conf"

if [[ ! -f "$GDM_CONF" ]]; then
    echo "   ⚠️  $GDM_CONF not found — is GDM3 installed?"
else
    # Check if [daemon] section exists and update/add the auto-login lines
    if grep -q "^AutomaticLoginEnable" "$GDM_CONF"; then
        sed -i "s/^AutomaticLoginEnable.*/AutomaticLoginEnable = true/" "$GDM_CONF"
        sed -i "s/^AutomaticLogin .*/AutomaticLogin = ${AUTO_LOGIN_USER}/" "$GDM_CONF"
    else
        # Insert auto-login lines under [daemon]
        sed -i "/^\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = ${AUTO_LOGIN_USER}" "$GDM_CONF"
    fi
    echo "   ✅ Auto-login enabled"
fi

# ──────────────────────────────────────────────────────────
# 2. Enable SSH
# ──────────────────────────────────────────────────────────
echo "🔑 Enabling SSH server..."

systemctl enable ssh --now
echo "   ✅ SSH enabled and started"

# ──────────────────────────────────────────────────────────
# 3. Install RustDesk
# ──────────────────────────────────────────────────────────
echo "🖥️  Installing RustDesk ${RUSTDESK_VERSION}..."

cd /tmp

if [[ ! -f "$RUSTDESK_DEB" ]]; then
    wget -q --show-progress "$RUSTDESK_URL" -O "$RUSTDESK_DEB"
fi

apt install -y "./$RUSTDESK_DEB"

systemctl enable rustdesk
systemctl start rustdesk

echo "   ✅ RustDesk installed and running"

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ All done!"
echo "============================================"
echo ""
echo "  Auto-login:  $AUTO_LOGIN_USER (takes effect next reboot)"
echo "  SSH:          $(systemctl is-active ssh) on port 22"
echo "  RustDesk:     $(systemctl is-active rustdesk) — open the app to get your ID"
echo ""
echo "  Reboot to apply auto-login:"
echo "    sudo reboot"
echo ""
