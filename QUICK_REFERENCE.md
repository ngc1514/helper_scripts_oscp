# Quick Reference Guide

## Script Names & Purpose

| Script | Purpose | Runs On | Requires Sudo |
|--------|---------|---------|---------------|
| **create-vm.sh** | Creates the VM infrastructure | Ubuntu host | Yes |
| **configure-kali.sh** | Configures Kali (auto-login, NoMachine, GNOME) | Inside Kali VM | Yes |
| **configure-vm-remote.sh** | Configures existing VM via SSH | Ubuntu host | No |
| **setup-kali-auto.sh** | Full automated setup (create + configure) | Ubuntu host | Yes |

## Quick Commands

### Automated Setup (Recommended for Headless)
```bash
# One command does everything
sudo ./setup-kali-auto.sh /path/to/kali.qcow2
```

### Manual Setup (Step-by-Step)
```bash
# Step 1: Create VM
sudo ./create-vm.sh /path/to/kali.qcow2

# Step 2: Configure VM remotely
./configure-vm-remote.sh

# Or configure manually via SSH
ssh kali@<kali-ip>
sudo ./configure-kali.sh
```

### Configure Existing VM
```bash
# If VM is already running
./configure-vm-remote.sh [optional-ip]
```

## Common Tasks

### Find VM IP
```bash
sudo virsh domifaddr kali
# or
sudo arp-scan --interface=br0 --localnet
```

### VM Management
```bash
# List VMs
sudo virsh list --all

# Start VM
sudo virsh start kali

# Shutdown VM
sudo virsh shutdown kali

# Force stop VM
sudo virsh destroy kali

# Check autostart status
sudo virsh dominfo kali | grep Autostart

# Enable autostart
sudo virsh autostart kali
```

### Access VM
```bash
# SSH
ssh kali@<kali-ip>

# NoMachine
# Download client from https://www.nomachine.com/download
# Connect to <kali-ip>:4000

# SPICE (from Ubuntu host with GUI)
virt-manager
```

## Customization

### Change Network Interface
Edit `create-vm.sh`:
```bash
PHYS_IFACE="eno1"  # Change to your interface name
```

### Customize Software Installation
Edit `configure-kali.sh` section 5:
```bash
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    # Add more here
)
```

### Add New Software
In `configure-kali.sh`, create a new function:
```bash
install_myapp() {
    echo "   📦 Installing MyApp..."
    # Installation commands here
    echo "      ✅ MyApp installed"
}
```

Then add to the array:
```bash
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    "install_myapp"  # Your new software
)
```

## Troubleshooting

### VM won't start
```bash
# Check VM status
sudo virsh list --all

# Check logs
sudo journalctl -u libvirtd -n 50

# Check if bridge exists
ip addr show br0
```

### Can't find VM IP
```bash
# Method 1: virsh
sudo virsh domifaddr kali

# Method 2: Get MAC and search ARP
VM_MAC=$(sudo virsh domiflist kali | grep br0 | awk '{print $5}')
ip neigh show | grep -i "$VM_MAC"

# Method 3: arp-scan
sudo arp-scan --interface=br0 --localnet
```

### SSH connection refused
```bash
# Check if VM is running
sudo virsh list

# Check if SSH port is open
nmap -p 22 <kali-ip>

# Inside VM (via console), check SSH
sudo virsh console kali
# Login and run:
sudo systemctl status ssh
sudo systemctl start ssh
```

### NoMachine not working
```bash
# SSH into VM
ssh kali@<kali-ip>

# Check NoMachine status
sudo systemctl status nxserver
sudo /usr/NX/bin/nxserver --status

# Check if port 4000 is listening
sudo ss -tlnp | grep 4000

# Restart NoMachine
sudo /usr/NX/bin/nxserver --restart

# Check logs
sudo tail -f /usr/NX/var/log/nxserver.log
```

## Default Credentials

- **Username:** kali
- **Password:** kali

⚠️ **Change these immediately for security!**

```bash
# Inside Kali VM
passwd kali
sudo passwd root
```

## File Locations

### On Ubuntu Host
- Scripts: `~/workspace/helper_scripts_oscp/`
- VM images: `~/vm/` (or wherever you extracted)
- Netplan config: `/etc/netplan/02-bridge.yaml`
- QEMU bridge config: `/etc/qemu/bridge.conf`

### Inside Kali VM
- LightDM config: `/etc/lightdm/lightdm.conf`
- GDM3 config: `/etc/gdm3/daemon.conf`
- SSH config: `/etc/ssh/sshd_config`
- NoMachine: `/usr/NX/`
- NoMachine logs: `/usr/NX/var/log/`

## Network Configuration

### Bridge Setup (Ubuntu Host)
```bash
# View bridge status
ip addr show br0
nmcli connection show netplan-br0

# Restart networking
sudo netplan apply

# Check NetworkManager connections
nmcli connection show
```

### Static IP (Optional)
Edit `/etc/netplan/02-bridge.yaml`:
```yaml
bridges:
  br0:
    interfaces: [eno1]
    dhcp4: false
    addresses:
      - 10.0.0.100/24
    routes:
      - to: default
        via: 10.0.0.1
    nameservers:
      addresses:
        - 8.8.8.8
```

Then apply:
```bash
sudo netplan apply
```

## Security Best Practices

1. **Change default passwords**
2. **Use SSH keys instead of passwords**
3. **Configure firewall (ufw)**
4. **Don't expose SSH/NoMachine to internet**
5. **Keep systems updated**

```bash
# Setup SSH keys
ssh-copy-id kali@<kali-ip>

# Disable password auth
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Basic firewall
sudo ufw allow from 10.0.0.0/24 to any port 22
sudo ufw allow from 10.0.0.0/24 to any port 4000
sudo ufw enable
```

## Additional Resources

- **HEADLESS_SETUP.md** - Detailed headless server configuration
- **HEADLESS_WORKFLOW.md** - Complete workflow guide with troubleshooting
- **SCRIPT_ARCHITECTURE.md** - Technical details about script relationships
- **README.md** - Full documentation with examples
