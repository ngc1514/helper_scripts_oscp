#!/usr/bin/env bash
#
# kali-post-setup.sh
# Run inside Kali after first boot.
#
# What it does:
#   1. Detects display manager (LightDM/GDM3) and enables auto-login
#   2. Enables SSH server on boot
#   3. Installs NoMachine for remote desktop access
#
# Usage:
#   chmod +x kali-post-setup.sh
#   sudo ./kali-post-setup.sh

set -euo pipefail

# Ensure TERM is set for any interactive tools
export TERM="${TERM:-xterm-256color}"

# ──────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────
AUTO_LOGIN_USER="kali"
NOMACHINE_VERSION="9.4.14_1"
NOMACHINE_DEB="nomachine_${NOMACHINE_VERSION}_amd64.deb"
NOMACHINE_URL="https://web9001.nomachine.com/download/9.4/Linux/${NOMACHINE_DEB}"

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
# Detect display manager
# ──────────────────────────────────────────────────────────
# The active display manager is a symlink at /etc/systemd/system/display-manager.service
# e.g. -> /lib/systemd/system/lightdm.service
DM_SERVICE=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null || echo "unknown")

echo "📋 Detected display manager: $DM_SERVICE"

# ──────────────────────────────────────────────────────────
# 1. Enable auto-login (adapts to LightDM or GDM3)
# ──────────────────────────────────────────────────────────
echo "🔓 Configuring auto-login for '$AUTO_LOGIN_USER'..."

case "$DM_SERVICE" in
    lightdm)
        # XFCE uses LightDM — config is in /etc/lightdm/lightdm.conf
        LIGHTDM_CONF="/etc/lightdm/lightdm.conf"

        # Create config if it doesn't exist
        if [[ ! -f "$LIGHTDM_CONF" ]]; then
            echo "[Seat:*]" > "$LIGHTDM_CONF"
        fi

        # Remove any existing autologin lines to avoid duplicates
        sed -i '/^autologin-user=/d' "$LIGHTDM_CONF"
        sed -i '/^autologin-user-timeout=/d' "$LIGHTDM_CONF"

        # Add autologin under [Seat:*]
        if grep -q '^\[Seat:\*\]' "$LIGHTDM_CONF"; then
            sed -i "/^\[Seat:\*\]/a autologin-user=${AUTO_LOGIN_USER}\nautologin-user-timeout=0" "$LIGHTDM_CONF"
        else
            echo -e "\n[Seat:*]\nautologin-user=${AUTO_LOGIN_USER}\nautologin-user-timeout=0" >> "$LIGHTDM_CONF"
        fi

        # LightDM requires the user to be in the 'autologin' group
        groupadd -f autologin
        usermod -aG autologin "$AUTO_LOGIN_USER"

        echo "   ✅ Auto-login enabled (LightDM → XFCE)"
        ;;

    gdm3|gdm)
        # GNOME uses GDM3 — config is in /etc/gdm3/daemon.conf
        GDM_CONF="/etc/gdm3/daemon.conf"

        if [[ ! -f "$GDM_CONF" ]]; then
            echo "   ⚠️  $GDM_CONF not found — is GDM3 installed?"
        else
            if grep -q "^AutomaticLoginEnable" "$GDM_CONF"; then
                sed -i "s/^AutomaticLoginEnable.*/AutomaticLoginEnable = true/" "$GDM_CONF"
                sed -i "s/^AutomaticLogin .*/AutomaticLogin = ${AUTO_LOGIN_USER}/" "$GDM_CONF"
            else
                sed -i "/^\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = ${AUTO_LOGIN_USER}" "$GDM_CONF"
            fi
            echo "   ✅ Auto-login enabled (GDM3 → GNOME)"
        fi
        ;;

    *)
        echo "   ⚠️  Unknown display manager '$DM_SERVICE' — skipping auto-login."
        echo "       Supported: lightdm (XFCE), gdm3 (GNOME)"
        ;;
esac

# ──────────────────────────────────────────────────────────
# 2. Enable SSH
# ──────────────────────────────────────────────────────────
echo "🔑 Enabling SSH server..."

systemctl enable ssh --now
echo "   ✅ SSH enabled and started"

# ──────────────────────────────────────────────────────────
# 3. Install NoMachine
# ──────────────────────────────────────────────────────────
echo "🖥️  Installing NoMachine ${NOMACHINE_VERSION}..."

cd /tmp

if [[ ! -f "$NOMACHINE_DEB" ]]; then
    wget -q --show-progress "$NOMACHINE_URL" -O "$NOMACHINE_DEB"
fi

dpkg -i "./$NOMACHINE_DEB" || apt install -f -y

# NoMachine installs its own service (nxserver) automatically.
# Verify it's running.
/usr/NX/bin/nxserver --status

echo "   ✅ NoMachine installed and running"

# ──────────────────────────────────────────────────────────
# 4. Switch Desktop Environment to GNOME
# ──────────────────────────────────────────────────────────
echo "🖥️  Switching desktop environment to GNOME..."
echo ""
echo "   This will:"
echo "   1. Update package lists"
echo "   2. Pre-configure GDM3 as default display manager"
echo "   3. Install kali-desktop-gnome (non-interactive)"
echo "   4. Set GNOME as default session manager"
echo "   5. Remove kali-desktop-xfce"
echo ""

# Update package lists
apt update

# Pre-seed debconf to select GDM3 as the default display manager
# This prevents the interactive dialog from appearing
echo "gdm3 shared/default-x-display-manager select gdm3" | debconf-set-selections
echo "lightdm shared/default-x-display-manager select gdm3" | debconf-set-selections

# Install GNOME desktop non-interactively
DEBIAN_FRONTEND=noninteractive apt install -y kali-desktop-gnome

# Set GNOME as the default session manager (non-interactive)
update-alternatives --set x-session-manager /usr/bin/gnome-session

# Ensure GDM3 is set as the display manager and enabled
systemctl disable lightdm.service 2>/dev/null || true
systemctl enable gdm3.service
systemctl set-default graphical.target

# Remove XFCE desktop
apt purge -y --autoremove --allow-remove-essential kali-desktop-xfce

echo ""
echo "   ✅ Desktop environment switch complete"

# ──────────────────────────────────────────────────────────
# 5. Install Third-Party Software
# ──────────────────────────────────────────────────────────
echo "📦 Installing third-party software..."
echo ""

# Define software installation functions
# Add new software by creating a new function following this pattern

install_brave() {
    echo "   🦁 Installing Brave Browser..."
    curl -fsS https://dl.brave.com/install.sh | sh
    echo "      ✅ Brave Browser installed"
}

install_sublime() {
    echo "   📝 Installing Sublime Text..."
    
    # Install GPG key
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | \
        tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
    
    # Add repository
    echo "deb https://download.sublimetext.com/ apt/stable/" | \
        tee /etc/apt/sources.list.d/sublime-text.list
    
    # Update and install
    apt update -qq
    apt install -y sublime-text
    
    echo "      ✅ Sublime Text installed"
}

# ──────────────────────────────────────────────────────────
# Configure which software to install
# Add or remove function names from this array
# ──────────────────────────────────────────────────────────
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    # Add more software installation functions here
    # Example: "install_vscode"
)

# ──────────────────────────────────────────────────────────
# Execute installations
# ──────────────────────────────────────────────────────────
for software_func in "${THIRD_PARTY_SOFTWARE[@]}"; do
    if declare -f "$software_func" > /dev/null; then
        $software_func
    else
        echo "   ⚠️  Function '$software_func' not found — skipping"
    fi
done

echo ""
echo "   ✅ Third-party software installation complete"

# ──────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ All done!"
echo "============================================"
echo ""
echo "  Display manager:  $DM_SERVICE"
echo "  Auto-login:       $AUTO_LOGIN_USER (takes effect next reboot)"
echo "  SSH:              $(systemctl is-active ssh) on port 22"
echo "  NoMachine:        installed — connect on port 4000 (NX protocol)"
echo "  Desktop:          GNOME (switched from XFCE)"
echo "  Brave Browser:    installed"
echo "  Sublime Text:     installed"
echo ""
echo "  Reboot to apply auto-login and desktop environment:"
echo "    sudo reboot"
echo ""
echo "  Then from your Mac/PC, install NoMachine client and connect"
echo "  to this machine's IP on port 4000."
echo ""
