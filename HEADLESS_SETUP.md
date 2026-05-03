# Headless Ubuntu Server Setup

This guide explains how to achieve a fully headless Ubuntu experience where you can power on your PC and immediately access it remotely without logging in locally.

## What the Setup Script Already Does

The `setup-kali-vm.sh` script automatically configures:

✅ **NetworkManager autoconnect** - Removes user-specific permissions from network connections
✅ **Bridge autostart** - Ensures br0 and eno1 connections start at boot
✅ **VM autostart** - Kali VM launches automatically when the host boots
✅ **Libvirt service** - Starts automatically at boot

## Additional Headless Optimizations (Optional)

### 1. Disable GUI Login (Recommended for Headless)

If you don't need the Ubuntu desktop at all, switch to multi-user (text) mode:

```bash
# Switch to text mode (no GUI)
sudo systemctl set-default multi-user.target

# To switch back to GUI mode later:
sudo systemctl set-default graphical.target
```

This saves resources and ensures everything starts without a display manager.

### 2. Enable Auto-Login to Console (Alternative)

If you want to keep the GUI but auto-login:

**For GDM3 (Ubuntu default):**
```bash
sudo mkdir -p /etc/gdm3
sudo tee /etc/gdm3/custom.conf > /dev/null << 'EOF'
[daemon]
AutomaticLoginEnable = true
AutomaticLogin = your-username
EOF
```

**For LightDM:**
```bash
sudo tee -a /etc/lightdm/lightdm.conf > /dev/null << 'EOF'
[Seat:*]
autologin-user=your-username
autologin-user-timeout=0
EOF
```

### 3. Enable SSH on Ubuntu Host

Access your Ubuntu host remotely:

```bash
sudo apt install -y openssh-server
sudo systemctl enable ssh --now
```

### 4. Configure Static IP (Optional)

For predictable access, set a static IP on your bridge:

Edit `/etc/netplan/02-bridge.yaml`:
```yaml
network:
  version: 2
  renderer: NetworkManager

  ethernets:
    eno1:
      dhcp4: false
      dhcp6: false

  bridges:
    br0:
      interfaces: [eno1]
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.0.0.100/24  # Your static IP
      routes:
        - to: default
          via: 10.0.0.1   # Your router IP
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
      parameters:
        stp: false
        forward-delay: 0
```

Then apply:
```bash
sudo netplan apply
```

### 5. Wake-on-LAN (Optional)

Enable WOL to power on your PC remotely:

```bash
# Check if your NIC supports WOL
sudo ethtool eno1 | grep Wake-on

# Enable WOL
sudo ethtool -s eno1 wol g

# Make it persistent (add to /etc/rc.local or create a systemd service)
sudo tee /etc/systemd/system/wol.service > /dev/null << 'EOF'
[Unit]
Description=Enable Wake-on-LAN on eno1
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s eno1 wol g

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable wol.service
```

## Verification

After setup, verify headless operation:

```bash
# Check network connections are set for autoconnect
nmcli connection show netplan-br0 | grep -E "permissions|autoconnect"
nmcli connection show netplan-eno1 | grep -E "permissions|autoconnect"

# Should show:
# connection.autoconnect: yes
# connection.permissions: --

# Check VM autostart
sudo virsh list --all --autostart

# Check libvirt service
sudo systemctl status libvirtd
```

## Typical Headless Workflow

1. **Power on Ubuntu PC** (press power button)
2. **Wait ~30-60 seconds** for boot and VM startup
3. **From your Mac:**
   ```bash
   # SSH to Ubuntu host
   ssh your-user@ubuntu-ip
   
   # Or SSH directly to Kali VM
   ssh kali@kali-ip
   
   # Or RDP to Kali VM
   # Open Microsoft Remote Desktop → kali-ip
   ```

## Troubleshooting

### Network doesn't start without login

Run the commands from the setup script manually:
```bash
sudo nmcli connection modify netplan-br0 connection.permissions ""
sudo nmcli connection modify netplan-br0 connection.autoconnect yes
sudo nmcli connection modify netplan-eno1 connection.permissions ""
sudo nmcli connection modify netplan-eno1 connection.autoconnect yes
```

### VM doesn't start automatically

```bash
# Check autostart status
sudo virsh dominfo kali | grep Autostart

# Enable if needed
sudo virsh autostart kali
```

### Can't access after reboot

1. Check if Ubuntu host is reachable (ping, check router DHCP leases)
2. SSH to Ubuntu host and check VM status: `sudo virsh list --all`
3. Check network: `ip addr show br0`
4. Check logs: `sudo journalctl -u libvirtd -u NetworkManager --since "10 minutes ago"`

## Security Considerations

⚠️ **Important:** Headless operation with auto-login reduces security. Consider:

- Use SSH keys instead of passwords
- Configure firewall rules (ufw)
- Keep systems updated
- Use strong passwords for remote access
- Consider VPN for remote access from outside your network
- Don't expose SSH/RDP directly to the internet

```bash
# Example: Basic firewall setup
sudo ufw allow from 10.0.0.0/24 to any port 22
sudo ufw allow from 10.0.0.0/24 to any port 3389
sudo ufw enable
```
