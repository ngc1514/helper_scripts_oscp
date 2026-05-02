# oscp_scripts

Helper scripts for OSCP lab setup and utilities.

## Kali VM Setup

### 1. Setup Kali VM on Ubuntu Host

This script sets up a bridged QEMU/KVM Kali Linux VM with autostart on an Ubuntu host.

**One-liner to extract and setup:**
```bash
cd ~/vm && 7z x ~/vm/kali-linux-2025.4-qemu-amd64.7z && sudo bash ~/workspace/helper_scripts_oscp/setup-kali-vm.sh ~/vm/kali-linux-2025.4-qemu-amd64.qcow2
```

**What it does:**
- Installs QEMU/KVM + libvirt
- Creates a br0 bridge on eno1 (netplan + NetworkManager)
- Imports the Kali qcow2 as a VM on the bridge (SPICE)
- Enables autostart so the VM launches on boot

**Prerequisites:**
- Ubuntu with netplan + NetworkManager
- Wired interface named eno1
- A pre-built Kali QEMU qcow2 image

⚠️ **WARNING:** This will briefly drop your wired network connection while the bridge is created. Have a fallback (WiFi, console).

### 2. Post-Setup Inside Kali VM

Run this script inside the Kali VM after first boot to configure auto-login, SSH, and NoMachine.

**Run via curl (from inside Kali):**
```bash
curl -fsSL https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/kali-post-setup.sh | sudo bash
```

**Or download and run:**
```bash
wget https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/kali-post-setup.sh
chmod +x kali-post-setup.sh
sudo ./kali-post-setup.sh
```

**What it does:**
- Detects display manager (LightDM/GDM3) and enables auto-login for 'kali' user
- Enables SSH server on boot
- Installs NoMachine for remote desktop access
- Switches desktop environment from XFCE to GNOME

**After running:**
```bash
sudo reboot
```

Then connect via:
- **SSH:** `ssh kali@<kali-ip>`
- **NoMachine:** Install NoMachine client and connect to `<kali-ip>:4000`

## Other Utilities

- **ftp_pull.py** - FTP file transfer utility
- **gobuster_filter.py** - Filter gobuster results