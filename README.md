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

#### Configuring Network Interface

If your wired network interface is **not** named `eno1`, you need to configure it before running the script:

1. Find your interface name:
```bash
ip link show
```

2. Edit `setup-kali-vm.sh` and update these variables at the top:
```bash
BRIDGE_NAME="br0"      # Bridge name (usually keep as br0)
PHYS_IFACE="eno1"      # Change this to your wired NIC name
```

Common interface names: `eth0`, `enp0s3`, `enp3s0`, `eno1`, `ens33`

**Headless Operation:**

The script automatically configures NetworkManager for headless operation, allowing your Ubuntu host to start networking and VMs without requiring user login. This means you can:
- Power on your Ubuntu PC
- Grab your Mac from another room
- SSH/RDP directly to your Kali VM

The script removes user-specific permissions from network connections and enables autoconnect, so everything starts at boot.

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
- Installs third-party software (Brave Browser, Sublime Text, etc.)

**After running:**
```bash
sudo reboot
```

Then connect via:
- **SSH:** `ssh kali@<kali-ip>`
- **NoMachine:** Install NoMachine client and connect to `<kali-ip>:4000`

#### Configuring Third-Party Software

The script includes a modular system for installing additional software. By default, it installs:
- **Brave Browser**
- **Sublime Text**

**To customize what gets installed:**

1. Open `kali-post-setup.sh` and find section 5
2. Add or remove software from the `THIRD_PARTY_SOFTWARE` array:

```bash
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    # Add more here
)
```

**To add new software:**

1. Create a new installation function following this pattern:

```bash
install_vscode() {
    echo "   💻 Installing VS Code..."
    # Add installation commands here
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/packages.microsoft.gpg
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    apt update -qq
    apt install -y code
    echo "      ✅ VS Code installed"
}
```

2. Add the function name to the `THIRD_PARTY_SOFTWARE` array:

```bash
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    "install_vscode"  # Your new software
)
```

**To skip all third-party software installations:**

Simply comment out or empty the array:

```bash
THIRD_PARTY_SOFTWARE=(
    # "install_brave"
    # "install_sublime"
)
```

## Other Utilities

- **ftp_pull.py** - FTP file transfer utility
- **gobuster_filter.py** - Filter gobuster results