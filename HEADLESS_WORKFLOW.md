# Headless Kali VM Workflow

This guide explains how to set up and access your Kali VM on a headless Ubuntu server without ever needing GUI access to the VM during setup.

## The Problem

When running Ubuntu headless (no monitor/keyboard), you face a chicken-and-egg problem:
- Your VM setup script creates a VM
- But you need GUI access to run the post-setup script that installs NoMachine
- NoMachine is what would give you GUI access

## The Solution

Use SSH to access the VM and run the post-setup script remotely. Your Kali VM already has SSH enabled by default, so you can access it over the network immediately after boot.

## Three Approaches

### Approach 1: Fully Automated (Recommended)

Use the complete setup script that does everything in one go:

```bash
# From your Ubuntu host
sudo ./setup-kali-auto.sh /path/to/kali.qcow2
```

This script:
1. Creates the VM using `create-vm.sh`
2. Waits for the VM to boot and get an IP
3. Waits for SSH to be available
4. Copies `configure-kali.sh` to the VM
5. Executes it via SSH
6. Reboots the VM
7. Gives you a fully configured system

**Time:** ~10-15 minutes (mostly waiting for package installations)

### Approach 2: Semi-Automated

Run the VM setup first, then use the remote configuration script:

```bash
# Step 1: Create the VM
sudo ./create-vm.sh /path/to/kali.qcow2

# Step 2: Wait a minute for boot, then configure remotely
./configure-vm-remote.sh

# Or specify IP manually
./configure-vm-remote.sh 10.0.0.123
```

**Advantage:** More control, can verify VM is running before configuration

### Approach 3: Manual SSH

For maximum control:

```bash
# Step 1: Create the VM
sudo ./create-vm.sh /path/to/kali.qcow2

# Step 2: Find the VM's IP
sudo virsh domifaddr kali
# or
sudo arp-scan --interface=br0 --localnet

# Step 3: SSH into the VM
ssh kali@<kali-ip>
# Password: kali

# Step 4: Download and run configuration
wget https://raw.githubusercontent.com/ngc1514/helper_scripts_oscp/refs/heads/main/configure-kali.sh
chmod +x configure-kali.sh
sudo ./configure-kali.sh

# Step 5: Reboot
sudo reboot
```

**Advantage:** Full visibility into each step

## Alternative: Pre-Configure the Image

If you want to avoid SSH entirely, you can inject the script into the qcow2 image **before** creating the VM:

```bash
# Install libguestfs-tools
sudo apt install -y libguestfs-tools

# Inject and run the script in the image
sudo virt-customize -a /path/to/kali.qcow2 \
  --upload configure-kali.sh:/root/configure-kali.sh \
  --chmod 0755:/root/configure-kali.sh \
  --run-command '/root/configure-kali.sh'

# Then create the VM as normal
sudo ./create-vm.sh /path/to/kali.qcow2
```

**Advantage:** VM is fully configured on first boot  
**Disadvantage:** Modifies the original image, takes longer

## Typical Headless Workflow

Once everything is set up, your typical workflow is:

1. **Power on Ubuntu server** (press power button or use Wake-on-LAN)
2. **Wait 30-60 seconds** for boot
3. **From your Mac/laptop:**
   ```bash
   # Option A: SSH to Kali directly
   ssh kali@<kali-ip>
   
   # Option B: NoMachine GUI
   # Open NoMachine client → Connect to <kali-ip>:4000
   
   # Option C: SSH to Ubuntu host first
   ssh your-user@<ubuntu-ip>
   # Then manage VMs: sudo virsh list --all
   ```

## Finding Your VM's IP

Multiple methods, in order of reliability:

```bash
# Method 1: virsh (may not work with bridged networks)
sudo virsh domifaddr kali

# Method 2: ARP cache
sudo ip neigh show | grep $(sudo virsh domiflist kali | grep br0 | awk '{print $5}')

# Method 3: arp-scan (most reliable)
sudo arp-scan --interface=br0 --localnet

# Method 4: Check your router's DHCP leases
# Look for hostname "kali" in your router's web interface
```

## Troubleshooting

### VM doesn't get an IP

```bash
# Check VM is running
sudo virsh list --all

# Check bridge is up
ip addr show br0

# Check VM network interface
sudo virsh domiflist kali

# Restart VM
sudo virsh shutdown kali
sudo virsh start kali
```

### Can't SSH to VM

```bash
# Check if SSH port is open (from Ubuntu host)
nmap -p 22 <kali-ip>

# Check if VM is reachable
ping <kali-ip>

# Try connecting with verbose output
ssh -v kali@<kali-ip>

# Check SSH is running inside VM (if you have console access)
sudo virsh console kali
# Login and check: sudo systemctl status ssh
```

### NoMachine not working after post-setup

```bash
# SSH into VM
ssh kali@<kali-ip>

# Check NoMachine status
sudo systemctl status nxserver

# Check if port 4000 is listening
sudo ss -tlnp | grep 4000

# Restart NoMachine
sudo /usr/NX/bin/nxserver --restart

# Check logs
sudo tail -f /usr/NX/var/log/nxserver.log
```

### Post-setup script fails

```bash
# SSH into VM
ssh kali@<kali-ip>

# Run script manually with verbose output
sudo bash -x ./configure-kali.sh

# Check for specific errors
sudo journalctl -xe
```

## Security Notes

⚠️ **Important:** This setup uses default credentials and auto-login for convenience. For production use:

1. **Change default passwords:**
   ```bash
   # On Kali VM
   passwd kali
   sudo passwd root
   ```

2. **Use SSH keys instead of passwords:**
   ```bash
   # From your Mac
   ssh-copy-id kali@<kali-ip>
   
   # Then disable password auth on Kali
   sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   sudo systemctl restart ssh
   ```

3. **Configure firewall:**
   ```bash
   # On Ubuntu host
   sudo ufw allow from 10.0.0.0/24 to any port 22
   sudo ufw enable
   ```

4. **Don't expose to internet:**
   - Keep your setup on a private network
   - Use VPN for remote access from outside
   - Never forward SSH/NoMachine ports directly to the internet

## Advanced: Serial Console Access

If you want console access without SSH, add a serial console to your VM:

Edit `setup-kali-vm.sh` and add to the `virt-install` command:
```bash
--console pty,target.type=serial \
```

Then access with:
```bash
sudo virsh console kali
```

This gives you a text console without needing network access.

## Summary

**For headless setup, use Approach 1 (fully automated):**
```bash
sudo ./setup-kali-auto.sh /path/to/kali.qcow2
```

**For ongoing access:**
- SSH: `ssh kali@<kali-ip>`
- NoMachine: Connect to `<kali-ip>:4000`

**Default credentials:** kali / kali

**Change them immediately for security!**
