# oscp_scripts

Helper scripts for OSCP lab setup and utilities.

## Kali VM Setup

### Quick Start: Fully Automated Setup

One command from a fresh Kali qcow2 to a configured, headless-accessible VM:

```bash
# Extract the Kali image
cd ~/vm && 7z x ~/vm/kali-linux-2025.4-qemu-amd64.7z

# Create the VM and configure it end-to-end (default: stock XFCE)
cd ~/workspace/helper_scripts_oscp
sudo ./setup-kali-auto.sh ~/vm/kali-linux-2025.4-qemu-amd64.qcow2

# Or, if you want GNOME instead of XFCE (see "Desktop Environment" below)
sudo ./setup-kali-auto.sh ~/vm/kali-linux-2025.4-qemu-amd64.qcow2 --desktop gnome
```

[setup-kali-auto.sh](setup-kali-auto.sh) does the following:

1. **Pre-boots disk customization** with `virt-customize` — sets the `kali` user password to `kali`, enables SSH, and installs `qemu-guest-agent` so SSH and the host↔guest channel are live on first boot.
2. **Creates the bridged VM** via [create-vm.sh](create-vm.sh) and adds a serial console for fallback access.
3. **Waits for the VM's IP** (via guest agent / ARP) and SSHes in. If Kali's first-boot init wipes the SSH config, the script automatically shuts the VM down, re-applies `virt-customize`, and retries.
4. **Runs [configure-kali.sh](configure-kali.sh) inside the VM** — auto-login, SSH on boot, NoMachine, the chosen desktop (XFCE by default, or GNOME with `--desktop gnome`), third-party apps. Graphics defaults to virtio+virgl (see [Graphics Mode](#graphics-mode-virtio-virgl-vs-qxl)).
5. **Reboots** and waits for the VM to come back online.

> If your wired interface is **not** `eno1`, see [Configuring Network Interface](#configuring-network-interface) before running.

**Prerequisites:**
- Ubuntu host with `netplan` + NetworkManager
- A pre-built Kali QEMU qcow2 image
- Wired interface named `eno1` (configurable — see below)
- `libguestfs-tools` and `sshpass` will be installed automatically if missing

> ⚠️ Bridge creation will briefly drop your wired connection. Have a fallback (WiFi, console).

---

### Desktop Environment: XFCE (default) vs GNOME

Two paths, pick one with `--desktop xfce|gnome` (defaults to `xfce`):

- **`--desktop xfce` (default)** — leaves Kali's stock XFCE in place. LightDM auto-login, no DE swap. **This is the recommended path if your primary access is NoMachine** — XFCE is lightweight, doesn't lean on a compositor, and feels noticeably snappier across the wire.
- **`--desktop gnome`** — installs `kali-desktop-gnome`, switches to GDM3 with auto-login, and removes XFCE. Prettier locally, but GNOME's animations + compositing make NoMachine sessions visibly laggy. Use this if you mostly access the VM directly (virt-manager/SPICE) and want the eye candy.

The flag is wired through both [setup-kali-auto.sh](setup-kali-auto.sh) and [configure-kali.sh](configure-kali.sh):

```bash
# Full automated setup with GNOME instead of XFCE
sudo ./setup-kali-auto.sh ~/vm/kali.qcow2 --desktop gnome

# Re-running configure-kali.sh inside an existing VM
sudo ./configure-kali.sh --desktop gnome
```

You can switch later by re-running `configure-kali.sh` with the other value — going XFCE → GNOME is what the GNOME branch already does; going GNOME → XFCE isn't automated (you'd have to `apt install kali-desktop-xfce && apt purge kali-desktop-gnome` yourself).

---

### Graphics Mode: virtio (virgl) vs qxl

Picked with `--graphics auto|virtio|qxl` on [setup-kali-auto.sh](setup-kali-auto.sh) / [create-vm.sh](create-vm.sh) (defaults to `auto`):

- **`virtio`** — virtio-gpu with `accel3d` (virgl), SPICE local-only with GL passthrough. The guest gets a real GPU pipeline, so anything OpenGL — compositors, GTK animations, browser scrolling, terminal GPU rendering — runs at GPU speed instead of llvmpipe software fallback. NoMachine then captures the smooth result, so this is the best NoMachine experience too. Local virt-manager benefits even more (DMA-BUF passthrough, ~60fps).
- **`qxl`** — plain QXL emulated GPU, SPICE listening on the network. No GL acceleration in the guest (everything OpenGL falls back to software). Slower but broadly compatible. Use this if you need remote SPICE, or with GNOME.
- **`auto` (default)** — pairs `virtio` with `--desktop xfce` and `qxl` with `--desktop gnome`. Forcing `--graphics virtio --desktop gnome` is allowed but warned: virgl + GNOME's mutter is the combo that breaks the compositor (rendering glitches, occasional fallback to XFCE).

Examples:

```bash
# Default: XFCE + virtio (best NoMachine + virt-manager perf)
sudo ./setup-kali-auto.sh ~/vm/kali.qcow2

# GNOME, auto-paired with qxl (avoids compositor breakage)
sudo ./setup-kali-auto.sh ~/vm/kali.qcow2 --desktop gnome

# Force qxl explicitly (e.g. you need SPICE listening on the network)
sudo ./setup-kali-auto.sh ~/vm/kali.qcow2 --graphics qxl

# Standalone create-vm.sh with explicit graphics
sudo ./create-vm.sh ~/vm/kali.qcow2 --graphics qxl
```

Switching later means editing the VM with `virsh edit kali`. The relevant blocks for each mode:

```xml
<!-- virtio + virgl -->
<graphics type='spice'>
  <listen type='none'/>
  <image compression='off'/>
  <gl enable='yes'/>
</graphics>
<video>
  <model type='virtio' heads='1' primary='yes'>
    <acceleration accel3d='yes'/>
  </model>
</video>

<!-- qxl + remote-listen SPICE -->
<graphics type='spice' autoport='yes' listen='0.0.0.0'/>
<video>
  <model type='qxl' primary='yes'/>
</video>
```

---

### Manual Setup (Step-by-Step)

If you want more control or are setting things up incrementally:

#### 1. Create the Kali VM

```bash
cd ~/vm && 7z x ~/vm/kali-linux-2025.4-qemu-amd64.7z
sudo bash ~/workspace/helper_scripts_oscp/create-vm.sh ~/vm/kali-linux-2025.4-qemu-amd64.qcow2
```

[create-vm.sh](create-vm.sh) installs QEMU/KVM + libvirt, creates a `br0` bridge on `eno1` (netplan + NetworkManager), imports the qcow2 as a VM on the bridge with the chosen graphics mode (virtio+virgl by default, see [Graphics Mode](#graphics-mode-virtio-virgl-vs-qxl)) plus a serial console and virtio guest-agent channel, and enables autostart.

This script does **not** pre-customize the disk — if you go this route, plan to either:
- Configure Kali interactively via SPICE/virt-manager, or
- Run [fix-kali-access.sh](fix-kali-access.sh) afterward to set the password and enable SSH (see [Troubleshooting](#troubleshooting)).

#### Configuring Network Interface

If your wired NIC is not `eno1`, edit [create-vm.sh](create-vm.sh):

```bash
BRIDGE_NAME="br0"      # bridge name (usually keep)
PHYS_IFACE="eno1"      # change to your wired NIC
```

Find your interface with `ip link show`. Common names: `eth0`, `enp0s3`, `enp3s0`, `eno1`, `ens33`.

#### Headless Host Operation

`create-vm.sh` configures NetworkManager so the bridge and physical interface autoconnect without requiring user login. The host can boot, bring up networking, and start the VM with no one logged in — you can then SSH or NoMachine straight into Kali from another machine.

#### 2. Configure Kali

[configure-kali.sh](configure-kali.sh) handles:
- Display manager auto-login (writes `lightdm.conf`, and also `gdm3/daemon.conf` if the GNOME switch is requested)
- SSH server on boot
- NoMachine install (skipped if already present)
- Optional desktop swap to GNOME via `--desktop gnome` (default keeps stock XFCE — see [Desktop Environment](#desktop-environment-xfce-default-vs-gnome))
- Third-party software (Brave, Sublime — configurable, see below)

Pick one of the following:

**Option A — Remote (recommended for headless hosts):**

```bash
chmod +x configure-vm-remote.sh
./configure-vm-remote.sh                            # auto-detect IP, default XFCE
./configure-vm-remote.sh 10.0.0.123                 # specify IP
./configure-vm-remote.sh 10.0.0.123 --desktop gnome # specify IP + GNOME swap
```

[configure-vm-remote.sh](configure-vm-remote.sh) auto-detects the VM's IP, waits for SSH, scps `configure-kali.sh` over, and runs it.

**Option B — Manual SSH:**

```bash
# Find the Kali IP from the host
sudo virsh domifaddr kali --source agent      # works now that qemu-guest-agent is installed
# fallback: sudo arp-scan --interface=br0 --localnet

ssh kali@<kali-ip>                            # default password: kali
# default XFCE:
curl -fsSL https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/configure-kali.sh | sudo bash
# or, GNOME swap — pipe via `bash -s --` so flags reach the script:
curl -fsSL https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/configure-kali.sh | sudo bash -s -- --desktop gnome
```

**Option C — From inside Kali (GUI/SPICE):**

```bash
wget https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/configure-kali.sh
chmod +x configure-kali.sh
sudo ./configure-kali.sh                  # default XFCE
sudo ./configure-kali.sh --desktop gnome  # GNOME swap
```

After it finishes:

```bash
sudo reboot
```

Then connect via:
- **SSH:** `ssh kali@<kali-ip>`
- **NoMachine:** install the client, connect to `<kali-ip>:4000`
- **Serial console:** `sudo virsh console kali` (Enter to attach, `Ctrl+]` to exit)

#### Customizing Third-Party Software

The third-party installer in [configure-kali.sh](configure-kali.sh) is driven by an array (section 5):

```bash
THIRD_PARTY_SOFTWARE=(
    "install_brave"
    "install_sublime"
    # add more here
)
```

To add new software, define an installer function and append it:

```bash
install_vscode() {
    echo "   💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/packages.microsoft.gpg
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    apt update -qq
    apt install -y code
    echo "      ✅ VS Code installed"
}
```

To skip third-party installs entirely, comment out or empty the array.

---

### Script Reference

`setup-kali-auto.sh` is the orchestrator. It calls `create-vm.sh` and `scp`s `configure-kali.sh` into the VM, and it inlines the logic of `configure-vm-remote.sh` (SSH-and-run) and `fix-kali-access.sh` (first-boot regression recovery). It does not invoke those two as subprocesses — they exist as standalone entry points for when you don't want the full chain.

Every other script is self-contained:

| Script | Runs on | Standalone? | Requires |
|---|---|---|---|
| [create-vm.sh](create-vm.sh) | Ubuntu host | ✅ | qcow2 image |
| [configure-kali.sh](configure-kali.sh) | Inside Kali VM | ✅ | root, internet |
| [configure-vm-remote.sh](configure-vm-remote.sh) | Ubuntu host | ✅ | running VM with SSH; `configure-kali.sh` in cwd |
| [fix-kali-access.sh](fix-kali-access.sh) | Ubuntu host | ✅ | existing VM named `kali` |
| [setup-kali-auto.sh](setup-kali-auto.sh) | Ubuntu host | orchestrator | `create-vm.sh` and `configure-kali.sh` in cwd |

**Common standalone use cases:**

- **Just want the VM, no Kali config** → `sudo ./create-vm.sh kali.qcow2`. Log in via SPICE/virt-manager afterward, or run `fix-kali-access.sh` to enable SSH.
- **VM already exists, just need to configure Kali** → `./configure-vm-remote.sh` from the host, or run `configure-kali.sh` directly inside the VM.
- **Locked out of an existing VM** → `sudo ./fix-kali-access.sh` resets credentials and re-enables SSH without rebuilding.
- **Re-running configuration** (e.g. you went XFCE first and now want GNOME) → `./configure-vm-remote.sh <ip> --desktop gnome`.

The thing `setup-kali-auto.sh` gives you that the pieces don't is the automatic chain — especially the inline first-boot regression recovery, which would otherwise require you to notice SSH failed and run `fix-kali-access.sh` manually.

---

### Troubleshooting

#### `fix-kali-access.sh` — recover SSH/console access

If the VM is up but SSH won't connect (wrong password, ssh disabled, first-boot config got clobbered), use [fix-kali-access.sh](fix-kali-access.sh):

```bash
sudo ./fix-kali-access.sh
```

It shuts the VM down, runs `virt-customize` to reset the `kali` password to `kali`, re-enables SSH, installs `qemu-guest-agent`, ensures a serial console is attached, restarts the VM, and waits for SSH to come back. Same remediation `setup-kali-auto.sh` runs inline when it detects a first-boot regression.

#### Useful `virsh` commands

```bash
sudo virsh list --all                         # list VMs
sudo virsh domifaddr kali --source agent      # VM IP via guest agent
sudo virsh console kali                       # serial console (Ctrl+] to exit)
sudo virsh shutdown kali                      # clean shutdown (uses guest agent)
sudo virsh start kali
```

---

## Other Utilities

- **[ftp_pull.py](ftp_pull.py)** — FTP file transfer utility
- **[gobuster_filter.py](gobuster_filter.py)** — filter gobuster results
