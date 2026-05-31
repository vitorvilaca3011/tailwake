# tailwake

**Wake-on-LAN + Sunshine readiness via Tailscale SSH** — turn on your desktop from anywhere using a relay device, then wait for Sunshine to be ready for Moonlight.

```

 █████████╗ █████╗ ██╗██╗     ██╗    ██╗ █████╗ ██╗  ██╗███████╗
 ╚══██╔══╝██╔══██╗██║██║     ██║    ██║██╔══██╗██║ ██╔╝██╔════╝
    ██║   ███████║██║██║     ██║ █╗ ██║███████║█████╔╝ █████╗
    ██║   ██╔══██║██║██║     ██║███╗██║██╔══██║██╔═██╗ ██╔══╝
    ██║   ██║  ██║██║███████╗╚███╔███╔╝██║  ██║██║  ██╗███████╗
    ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝

```

## Architecture

```
[Laptop] ---- SSH via Tailscale ----> [Relay device] -- WoL UDP --> [Desktop]
     │                                  LAN (192.168.1.x)           192.168.1.100
     │                                                             + Sunshine :47990
     └────────── Moonlight (WAN/remote) ────────────────────────────┘
```

1. Your laptop connects via **SSH + Tailscale** to a relay device on your local network. The relay can be an Android phone, Raspberry Pi, NAS, or any always-on Linux machine.
2. The relay sends **Wake-on-LAN magic packets** over UDP broadcast on the local LAN — this wakes your desktop.
3. The script waits for **Sunshine** (port 47990) to be ready so you can stream with Moonlight.

### Network notes

- **Laptop and relay** need to be connected over Tailscale (or another private network).
- **Desktop does not need Tailscale** — WoL is a local broadcast, and Sunshine/Moonlight can work over LAN or Tailscale.

The relay can be any device on your LAN that you can reach over Tailscale:
- 📱 **Android phone with Termux** (the most tested setup)
- 🥧 **Raspberry Pi** running Linux
- 💻 **Old mini PC or laptop**
- 🗄️ **NAS** with Docker or native SSH
- 🐧 **Any Linux box** on the same network

> **Android/Termux** is the primary tested relay. Generic Linux relays should work if they provide SSH, Python 3 and a POSIX shell.

## Requirements

- **Relay device:** SSH + Python 3. Tailscale strongly recommended for secure remote access.
- **Desktop:** Ethernet NIC with WoL support, Fast Startup disabled (Windows), [Sunshine](https://app.lizardbyte.dev/Sunshine/) (optional).
- **Laptop:** Linux/macOS with Bash and SSH client.
- **Tailscale** between the laptop and the relay (or any private network that connects them).
- **Desktop does not need Tailscale** for WoL itself (it's a LAN broadcast), but it does need to be reachable by Moonlight/Sunshine after boot.

## Quick start

```bash
# 1. Clone
git clone https://github.com/youruser/tailwake.git
cd tailwake

# 2. Create config from the example
cp tailwake.env.example tailwake.env
vim tailwake.env
# Fill in: RELAY_USER, RELAY_HOST, DESKTOP_MAC, DESKTOP_IP, BROADCAST

# 3. Set up SSH key to the relay
ssh-keygen -t ed25519 -f ~/.ssh/tailwake -N ""
ssh-copy-id -p 8022 -i ~/.ssh/tailwake.pub termux_user@100.x.x.x

# 4. Configure the relay (installs Python + WoL scripts)
./tailwake.sh setup

# 5. Test
./tailwake.sh doctor
```

## Config file locations

tailwake loads config in this order (first found wins):

1. `--config /path/to/file.env`
2. `./tailwake.env` (project directory)
3. `~/.config/tailwake/tailwake.env` (user-wide)

**Do not commit `tailwake.env`** — it contains your IPs and MAC addresses. The `.gitignore` already excludes it.

## Usage

```bash
./tailwake.sh                    # Full automation (recommended)
./tailwake.sh wake-and-wait      # Send WoL and wait for Sunshine
./tailwake.sh wait               # Wait for Sunshine only (no WoL)
./tailwake.sh wake               # Send WoL only
./tailwake.sh sunshine           # Check if Sunshine is ready (TCP :47990)
./tailwake.sh status             # Detailed status
./tailwake.sh doctor             # Full diagnostics
./tailwake.sh setup              # (Re)configure the relay
./tailwake.sh test-ssh           # Test SSH connection to relay
./tailwake.sh help               # Show this help
```

### Auto flow (`./tailwake.sh`)

1. Test SSH connection to the relay
2. Check if Sunshine is already online (TCP :47990)
3. Configure the relay if needed (auto-setup)
4. Send 5 WoL magic packets via UDP broadcast
5. Wait 30s boot grace period
6. Check Sunshine every 5s (max 180s / 36 attempts)
7. Show "ready for Moonlight" or error diagnostics

### Status output

```
Relay SSH    @ termux_user@100.x.x.x:8022  ... OK
Desktop ping @ 192.168.1.100                ... FAIL
Sunshine TCP @ 192.168.1.100:47990          ... OK
```

Sunshine TCP is the primary readiness indicator. Ping is best-effort — it may be blocked on Android/Termux.

## Desktop setup (Windows)

### Disable Fast Startup (required)

```cmd
powercfg /H off
```

Or: Control Panel > Power Options > "Choose what the power buttons do" > "Change settings that are currently unavailable" > Uncheck "Turn on fast startup".

### Network driver

Device Manager > Network Adapters > Realtek PCIe GbE Family Controller > Properties:
- **Advanced:** "Wake on Magic Packet" = Enabled
- **Power Management:** "Allow this device to wake the computer" ✓
- **Power Management:** "Only allow a magic packet to wake the computer" ✓

### Sunshine

[Sunshine](https://app.lizardbyte.dev/Sunshine/) is a self-hosted game stream host (like GeForce Experience). If you use Moonlight on your client:

- Install Sunshine on the desktop, set it to start automatically
- Default port: 47990 (TCP/UDP)
- tailwake waits for this port before declaring the desktop ready

### BIOS/UEFI

- "Resume PCI-E Device" = Enabled (essential for Ethernet WoL)
- "Wake on LAN" = Enabled
- "Fast Boot" = Disabled (if available)

## Android/Termux tips

For a reliable 24/7 relay on Android with Termux:

| Setting | Recommendation |
|---|---|
| Battery optimization | Set Termux to **Not optimized / Unrestricted** |
| Tailscale VPN | Enable **Always-on VPN** in Android settings |
| Wi-Fi during sleep | Set to **Always on** (if available) |
| Wakelock | Run `termux-wake-lock` to keep the SSH server alive |
| SSH server | `pkg install openssh && sshd` (listens on port 8022) |
| Autostart | Use Termux:Boot or a cron-like approach |

## Project structure

```
tailwake/
├── CHANGELOG.md
├── LICENSE
├── README.md
├── tailwake.sh               # Main script
├── tailwake.env.example      # Example config (safe to commit)
└── .gitignore                # Excludes tailwake.env
```

On the relay (installed via `setup`):
```
~/tailwake/wake_desktop.py    # Python WoL sender
~/bin/wake-desktop            # Wrapper executed by the script
```

## Customization

```bash
RELAY_USER="termux_user"                  # SSH username
RELAY_HOST="100.x.x.x"                    # Tailscale IP
RELAY_PORT="8022"                         # SSH port
DESKTOP_MAC="AA:BB:CC:DD:EE:FF"           # Target MAC
DESKTOP_IP="192.168.1.100"                # Target IP
BROADCAST="192.168.1.255"                 # LAN broadcast
WOL_PORT="9"                              # WoL UDP port
SUNSHINE_HOST="${DESKTOP_IP}"             # Sunshine host
SUNSHINE_PORT="47990"                     # Sunshine TCP port
WAIT_TIMEOUT="180"                        # Max wait (s)
WAIT_INTERVAL="5"                         # Check interval (s)
BOOT_GRACE_SECONDS="30"                   # Delay after WoL (s)
```

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Desktop won't turn on | Fast Startup | `powercfg /H off` |
| Packets sent, no response | AP Isolation | Check router: WiFi→Ethernet broadcast |
| Sunshine never ready | Firewall | Allow port 47990 TCP in Windows Firewall |
| SSH timeout | Phone sleeping | termux-wake-lock + disable battery optimization |
| Connection reset | sshd MaxStartups | Wait a few seconds between commands |

## Security notes

- **Do not expose SSH publicly.** Use Tailscale instead of port forwarding.
- **Use SSH keys**, not passwords. tailwake.sh works best with key-based auth.
- **Never commit `tailwake.env`** — it contains IPs and MAC addresses. The `.gitignore` handles this.
- **Never commit private SSH keys.** `~/.ssh/tailwake` is outside the repo.
- The `doctor` command prints metadata (IPs, MAC, ports). Review logs before pasting them publicly.

## License

MIT — see [LICENSE](LICENSE).
