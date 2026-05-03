# Script Architecture & Relationships

## Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    setup-kali-auto.sh                           │
│                    (Master Orchestrator)                        │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Step 1: bash create-vm.sh                                 │ │
│  │         ↓                                                  │ │
│  │         Creates VM, bridge, enables autostart             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Step 2: Wait for VM boot & detect IP                      │ │
│  │         ↓                                                  │ │
│  │         Polls ARP cache / arp-scan for VM MAC             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Step 3: Wait for SSH availability                         │ │
│  │         ↓                                                  │ │
│  │         Tests SSH connection every 2 seconds              │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Step 4: scp configure-kali.sh to VM                       │ │
│  │         ssh kali@IP "sudo ./configure-kali.sh"            │ │
│  │         ↓                                                  │ │
│  │         Runs inside VM: NoMachine, GNOME, etc.            │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Step 5: ssh kali@IP "sudo reboot"                         │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Individual Scripts (Standalone Use)

```
┌──────────────────────┐
│ create-vm.sh         │  ← Run this first
│                      │
│ Creates VM           │
│ Sets up bridge       │
│ Enables autostart    │
└──────────────────────┘
          ↓
    VM is running
    SSH is enabled
          ↓
┌──────────────────────┐
│ configure-vm-remote  │  ← Run this second (optional helper)
│                      │
│ Auto-detects IP      │
│ Waits for SSH        │
│ Copies & runs        │
│ configure-kali.sh    │
└──────────────────────┘
          ↓
    OR manually:
          ↓
┌──────────────────────┐
│ ssh kali@<ip>        │  ← Manual approach
│ ./configure-kali.sh  │
└──────────────────────┘
```

## Code Reuse Analysis

### `configure-vm-remote.sh` vs `setup-kali-auto.sh`

Both scripts share the same core logic for Steps 2-4:

| Function | configure-vm-remote.sh | setup-kali-auto.sh |
|----------|---------------------|------------------------|
| **Detect VM IP** | ✅ Lines 30-50 | ✅ Lines 75-95 |
| **Wait for SSH** | ✅ Lines 80-95 | ✅ Lines 110-125 |
| **Copy script** | ✅ Line 105 | ✅ Line 135 |
| **Execute script** | ✅ Lines 115-120 | ✅ Lines 140-145 |
| **Create VM** | ❌ (assumes exists) | ✅ Line 65 |
| **Reboot VM** | ❌ (optional) | ✅ Lines 155-175 |

### Why Two Scripts?

**`configure-vm-remote.sh`** - For existing VMs
- You already ran `create-vm.sh` yesterday
- VM is running, you just need to configure it
- More flexible (can specify IP manually)

**`setup-kali-auto.sh`** - For fresh setups
- Starting from scratch with a qcow2 image
- Want everything done in one command
- Includes VM creation + configuration

## Execution Contexts

```
┌─────────────────────────────────────────────────────────────┐
│                    Ubuntu Host (Headless)                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ create-vm.sh                                        │   │
│  │ • Runs as root (sudo)                               │   │
│  │ • Installs packages on host                         │   │
│  │ • Creates libvirt VM                                │   │
│  │ • Configures host networking                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ configure-vm-remote.sh / setup-kali-auto.sh         │   │
│  │ • Runs on host                                      │   │
│  │ • Uses SSH/SCP to communicate with VM               │   │
│  │ • Orchestrates remote execution                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            │ SSH/SCP                        │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Kali VM (Guest)                        │   │
│  │                                                     │   │
│  │  ┌───────────────────────────────────────────────┐ │   │
│  │  │ configure-kali.sh                             │ │   │
│  │  │ • Runs inside VM as root                      │ │   │
│  │  │ • Installs packages in VM                     │ │   │
│  │  │ • Configures VM settings                      │ │   │
│  │  │ • Installs NoMachine, GNOME, etc.             │ │   │
│  │  └───────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Usage Decision Tree

```
Do you have a qcow2 image and want everything automated?
│
├─ YES → sudo ./setup-kali-auto.sh /path/to/kali.qcow2
│         (Creates VM + configures it automatically)
│
└─ NO → Do you already have a running VM?
        │
        ├─ YES → ./configure-vm-remote.sh
        │         (Just configures existing VM)
        │
        └─ NO → Run manually:
                1. sudo ./create-vm.sh /path/to/kali.qcow2
                2. Wait for boot
                3. ssh kali@<ip>
                4. sudo ./configure-kali.sh
```

## Key Differences Summary

| Aspect | create-vm.sh | configure-kali.sh | configure-vm-remote.sh | setup-kali-auto.sh |
|--------|------------------|-------------------|---------------------|----------------------|
| **Runs on** | Ubuntu host | Kali VM | Ubuntu host | Ubuntu host |
| **Requires sudo** | Yes | Yes | No (uses sshpass) | Yes |
| **Creates VM** | Yes | No | No | Yes (calls create-vm.sh) |
| **Configures VM** | No | Yes | No (calls configure-kali.sh) | Yes (via SSH) |
| **Needs SSH** | No | No | Yes | Yes |
| **Standalone** | Yes | Yes | No (needs running VM) | Yes |
| **Use case** | Create VM | Configure VM | Automate config | Full automation |

## Code Sharing

The scripts share common patterns but are **not** dependent on each other:

```bash
# setup-kali-auto.sh does NOT call configure-vm-remote.sh
# Instead, it duplicates the logic inline for better control

# This is intentional because:
# 1. setup-kali-auto.sh needs to run as root (for VM creation)
# 2. configure-vm-remote.sh is designed to run as regular user
# 3. Error handling differs (complete setup is more strict)
# 4. Keeps each script self-contained and maintainable
```

## Example Scenarios

### Scenario 1: Fresh Setup, Headless Server
```bash
# One command does everything
sudo ./setup-kali-auto.sh ~/vm/kali.qcow2

# Internally runs:
# 1. create-vm.sh (creates VM)
# 2. Wait for boot
# 3. SSH + run configure-kali.sh
# 4. Reboot
```

### Scenario 2: VM Already Running, Need to Configure
```bash
# Just run the remote configuration script
./configure-vm-remote.sh

# Internally runs:
# 1. Find VM IP
# 2. Wait for SSH
# 3. Copy configure-kali.sh
# 4. Execute it via SSH
```

### Scenario 3: Manual Control
```bash
# Step by step
sudo ./create-vm.sh ~/vm/kali.qcow2
# ... wait for boot ...
ssh kali@10.0.0.123
sudo ./configure-kali.sh
sudo reboot
```

### Scenario 4: Pre-Configure Image (No SSH Needed)
```bash
# Inject script into image before VM creation
sudo virt-customize -a ~/vm/kali.qcow2 \
  --upload configure-kali.sh:/root/configure-kali.sh \
  --run-command '/root/configure-kali.sh'

# Then create VM (already configured)
sudo ./create-vm.sh ~/vm/kali.qcow2
```

## Summary

- **`create-vm.sh`** = VM creation (host-side)
- **`configure-kali.sh`** = VM configuration (guest-side)
- **`configure-vm-remote.sh`** = Bridge script (host → guest via SSH)
- **`setup-kali-auto.sh`** = All-in-one orchestrator (combines all three)

The relationship is **orchestration**, not **inheritance**. Each script is standalone, but the auto/remote scripts orchestrate the others via SSH.
