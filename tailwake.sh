#!/usr/bin/env bash
#
# tailwake — Wake-on-LAN + Sunshine readiness via Tailscale + SSH
#
# Turn on your desktop from anywhere using a relay device
# (Android/Termux, Raspberry Pi, mini PC, NAS, or Linux box).
#
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
#  DEFAULTS (overridden by tailwake.env)
# ═══════════════════════════════════════════════════════════════════════════════

RELAY_USER=""
RELAY_HOST=""
RELAY_PORT="8022"

DESKTOP_MAC=""
DESKTOP_IP=""
BROADCAST=""
WOL_PORT="9"

SUNSHINE_HOST=""
SUNSHINE_PORT="47990"

WAIT_TIMEOUT="180"
WAIT_INTERVAL="5"
BOOT_GRACE_SECONDS="30"

# ═══════════════════════════════════════════════════════════════════════════════
#  CONFIG LOADING
# ═══════════════════════════════════════════════════════════════════════════════

load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        set -a
        source "$config_file"
        set +a
        return 0
    fi
    return 1
}

find_config() {
    # 1. --config flag already handled by caller
    # 2. ./tailwake.env
    if [[ -f "./tailwake.env" ]]; then
        load_config "./tailwake.env" && return 0
    fi
    # 3. ~/.config/tailwake/tailwake.env
    if [[ -f "${HOME}/.config/tailwake/tailwake.env" ]]; then
        load_config "${HOME}/.config/tailwake/tailwake.env" && return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SSH — options come before the target (user@host)
# ═══════════════════════════════════════════════════════════════════════════════

SSH_TARGET=""
SSH_OPTS=()

build_ssh_cmd() {
    SSH_TARGET="${RELAY_USER}@${RELAY_HOST}"

    mkdir -p "${HOME}/.ssh/cm" 2>/dev/null || true

    SSH_OPTS=(
        -p "${RELAY_PORT}"
        -o ControlMaster=auto
        -o ControlPath="${HOME}/.ssh/cm/tailwake-%C"
        -o ControlPersist=600
        -o PasswordAuthentication=no
    )

    if [[ -f "${HOME}/.ssh/tailwake" ]]; then
        SSH_OPTS+=(-i "${HOME}/.ssh/tailwake")
    fi
}

ssh_relay() {
    if [[ ${#SSH_OPTS[@]} -eq 0 ]]; then
        error "SSH not configured. Run doctor or check your config."
        return 1
    fi
    ssh "${SSH_OPTS[@]}" "${SSH_TARGET}" "$@"
}

ssh_close() {
    ssh -O stop "${SSH_OPTS[@]}" "${SSH_TARGET}" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  COLORS
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -t 1 ]]; then
    BOLD='\033[1m';          DIM='\033[2m'
    GREEN='\033[0;32m';      BRIGHT_GREEN='\033[1;32m'
    YELLOW='\033[1;33m';     RED='\033[0;31m'
    BRIGHT_RED='\033[1;31m'; CYAN='\033[0;36m'
    BRIGHT_CYAN='\033[1;36m'; NC='\033[0m'
else
    BOLD=''; DIM=''; GREEN=''; BRIGHT_GREEN=''; YELLOW=''
    RED=''; BRIGHT_RED=''; CYAN=''; BRIGHT_CYAN=''; NC=''
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  LOG HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

ok()      { printf " ${GREEN}[ok]${NC}\n"; }
fail()    { printf " ${RED}[fail]${NC}\n"; }
info()    { printf "${GREEN}[*]${NC} %s\n" "$*"; }
success() { printf "${BRIGHT_GREEN}[+]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[-]${NC} %s\n" "$*"; }
error()   { printf "${BRIGHT_RED}[!]${NC} %s\n" "$*" >&2; }
step()    { printf "${CYAN}[>]${NC} %s" "$*"; }
detail()  { printf "${DIM}  %s${NC}\n" "$*"; }

banner() {
    echo ""
    printf "${GREEN}  █████████╗ █████╗ ██╗██╗     ██╗    ██╗ █████╗ ██╗  ██╗███████╗${NC}\n"
    printf "${GREEN}  ╚══██╔══╝██╔══██╗██║██║     ██║    ██║██╔══██╗██║ ██╔╝██╔════╝${NC}\n"
    printf "${GREEN}     ██║   ███████║██║██║     ██║ █╗ ██║███████║█████╔╝ █████╗  ${NC}\n"
    printf "${GREEN}     ██║   ██╔══██║██║██║     ██║███╗██║██╔══██║██╔═██╗ ██╔══╝  ${NC}\n"
    printf "${GREEN}     ██║   ██║  ██║██║███████╗╚███╔███╔╝██║  ██║██║  ██╗███████╗${NC}\n"
    printf "${GREEN}     ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝${NC}"
    echo ""; echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  CORE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# ── 1. help ──────────────────────────────────────────────────────────────────
usage() {
    banner
    printf "${BOLD}  usage:${NC}\n"
    echo ""
    printf "    ./tailwake.sh                      — WoL + wait for Sunshine\n"
    printf "    ./tailwake.sh ${GREEN}help${NC}               — show this help\n"
    printf "    ./tailwake.sh ${GREEN}wake-and-wait${NC}      — send WoL and wait for Sunshine\n"
    printf "    ./tailwake.sh ${GREEN}wait${NC}               — wait for Sunshine (no WoL)\n"
    printf "    ./tailwake.sh ${GREEN}wake${NC}               — send WoL only\n"
    printf "    ./tailwake.sh ${GREEN}sunshine${NC}           — check if Sunshine is ready\n"
    printf "    ./tailwake.sh ${GREEN}status${NC}             — detailed status\n"
    printf "    ./tailwake.sh ${GREEN}doctor${NC}             — full diagnostics\n"
    printf "    ./tailwake.sh ${GREEN}setup${NC}              — (re)configure the relay\n"
    printf "    ./tailwake.sh ${GREEN}test-ssh${NC}           — test SSH connection\n"
    echo ""
    printf "${BOLD}  configuration:${NC}\n"
    echo ""
    printf "    ${DIM}--config <file>${NC}  load config from custom path\n"
    printf "    ${DIM}./tailwake.env${NC}   auto-loaded if present\n"
    printf "    ${DIM}~/.config/tailwake/${NC}\n"
    echo ""
    printf "${BOLD}  targets (from config):${NC}\n"
    echo ""
    if [[ -n "${RELAY_HOST}" ]]; then
        printf "    ${CYAN}relay${NC}      ${DIM}→${NC} ${RELAY_USER}@${RELAY_HOST}:${RELAY_PORT}\n"
        printf "    ${CYAN}desktop${NC}    ${DIM}→${NC} ${DESKTOP_MAC} @ ${DESKTOP_IP}\n"
        printf "    ${CYAN}LAN${NC}        ${DIM}→${NC} ${BROADCAST}:${WOL_PORT}\n"
        printf "    ${CYAN}Sunshine${NC}   ${DIM}→${NC} ${SUNSHINE_HOST}:${SUNSHINE_PORT}\n"
    else
        printf "    ${YELLOW}(not configured — run ./tailwake.sh doctor)${NC}\n"
    fi
    echo ""
}

# ── 2. test-ssh ──────────────────────────────────────────────────────────────
cmd_test_ssh() {
    step "connecting to relay ${SSH_TARGET}:${RELAY_PORT} ..."
    if ssh_relay "echo alive" >/dev/null 2>&1; then
        ok
        success "relay online on Tailnet"
        return 0
    else
        fail
        error "relay unreachable. Check:"
        detail "relay powered on and on Tailnet?"
        detail "sshd running on relay (port ${RELAY_PORT})?"
        detail "ssh -p ${RELAY_PORT} ${SSH_TARGET}"
        return 1
    fi
}

# ── 3. remote_tcp_check ───────────────────────────────────────────────────────
# Tests TCP connectivity via Python on the relay. No external deps needed.
remote_tcp_check() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    # Safe-quote arguments for the remote shell (avoids injection via printf %q)
    local q_host q_port q_timeout
    printf -v q_host '%q' "$host"
    printf -v q_port '%q' "$port"
    printf -v q_timeout '%q' "$timeout"

    # Detect python3 or python on the relay, then exec the heredoc with quoted args
    ssh_relay \
        "PYTHON_BIN=\$(command -v python3 || command -v python) || { echo '[!] Python not found on relay' >&2; exit 127; }; exec \"\$PYTHON_BIN\" - ${q_host} ${q_port} ${q_timeout}" \
        <<'PYEOF'
import socket
import sys

if len(sys.argv) != 4:
    msg = "[!] expected 3 args: host port timeout, got {}"
    print(msg.format(len(sys.argv) - 1), file=sys.stderr)
    sys.exit(2)

host = sys.argv[1]
port = int(sys.argv[2])
timeout = float(sys.argv[3])

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(timeout)
try:
    s.connect((host, port))
    sys.exit(0)
except Exception:
    sys.exit(1)
finally:
    s.close()
PYEOF
}

# ── 4. check_sunshine ─────────────────────────────────────────────────────────
check_sunshine() {
    if remote_tcp_check "${SUNSHINE_HOST}" "${SUNSHINE_PORT}" "5"; then
        success "Sunshine ready at ${SUNSHINE_HOST}:${SUNSHINE_PORT}"
        return 0
    else
        warn "Sunshine not ready at ${SUNSHINE_HOST}:${SUNSHINE_PORT}"
        return 1
    fi
}

# ── 5. wait_for_sunshine ─────────────────────────────────────────────────────
wait_for_sunshine() {
    local max_attempts
    max_attempts=$(( WAIT_TIMEOUT / WAIT_INTERVAL ))

    info "waiting for Sunshine at ${SUNSHINE_HOST}:${SUNSHINE_PORT}"
    detail "timeout: ${WAIT_TIMEOUT}s | interval: ${WAIT_INTERVAL}s | max: ${max_attempts}x"
    echo ""

    for i in $(seq 1 "${max_attempts}"); do
        printf "  ${CYAN}[${i}/${max_attempts}]${NC} checking ${SUNSHINE_HOST}:${SUNSHINE_PORT} ... "
        set +e
        if remote_tcp_check "${SUNSHINE_HOST}" "${SUNSHINE_PORT}" "3" >/dev/null 2>&1; then
            printf "${GREEN}connected${NC}\n"
            echo ""
            success "Sunshine ready at ${SUNSHINE_HOST}:${SUNSHINE_PORT}"
            set -e
            return 0
        fi
        set -e
        printf "${DIM}waiting${NC}\n"
        sleep "${WAIT_INTERVAL}"
    done

    echo ""
    warn "Sunshine did not respond after ${WAIT_TIMEOUT}s at ${SUNSHINE_HOST}:${SUNSHINE_PORT}"
    return 1
}

# ── 6. sunshine (direct command) ──────────────────────────────────────────────
cmd_sunshine() {
    check_sunshine
}

# ── 7. setup ─────────────────────────────────────────────────────────────────
cmd_setup() {
    info "configuring relay remotely via SSH"
    echo ""

    step "creating ~/tailwake/ ..."
    ssh_relay "mkdir -p ~/tailwake"
    ok

    step "creating ~/bin/ ..."
    ssh_relay "mkdir -p ~/bin"
    ok

    echo ""
    info "checking Python on relay ..."
    local remote_python=""
    set +e
    remote_python="$(ssh_relay "command -v python3 || command -v python" 2>/dev/null)"
    set -e

    if [[ -z "$remote_python" ]]; then
        # Check if Termux (pkg) is available
        local has_pkg=false
        set +e
        ssh_relay "command -v pkg" >/dev/null 2>&1 && has_pkg=true
        set -e

        if $has_pkg; then
            warn "Python not found on relay. Installing via pkg ..."
            step "  pkg update ..."
            if ssh_relay "pkg update -y 2>&1"; then
                ok
            else
                fail
                error "pkg update failed. Run manually on the relay device:"
                detail "pkg update && pkg install python"
                return 1
            fi
            step "  pkg install python ..."
            if ssh_relay "pkg install -y python 2>&1"; then
                ok
            else
                fail
                error "Failed to install Python. Run manually:"
                detail "pkg update && pkg install python"
                return 1
            fi
            set +e
            remote_python="$(ssh_relay "command -v python3 || command -v python" 2>/dev/null)"
            set -e
        else
            error "Python 3 not found on relay and pkg is not available."
            detail "Install Python 3 manually on the relay device, then run setup again."
            detail "  Relay tip (Termux): pkg install python"
            detail "  Relay tip (Linux):  use your system package manager"
            return 1
        fi
    fi
    success "Python: ${remote_python}"

    echo ""
    info "detecting remote shell ..."
    local remote_shell=""
    set +e
    remote_shell="$(ssh_relay "command -v bash || command -v sh" 2>/dev/null)"
    set -e
    if [[ -z "$remote_shell" ]]; then
        error "Could not find a POSIX shell on the relay."
        return 1
    fi
    success "Shell: ${remote_shell}"

    echo ""
    step "generating ~/tailwake/wake_desktop.py ..."
    ssh_relay "cat > ~/tailwake/wake_desktop.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Wake-on-LAN magic packet sender.
Standard library only -- no external packages required.
"""

import argparse
import re
import socket
import sys
import time


def normalize_mac(mac: str) -> str:
    mac = mac.strip().upper().replace("-", "").replace(":", "")
    if not re.fullmatch(r'[0-9A-F]{12}', mac):
        raise ValueError(f"Invalid MAC: {mac!r}")
    return mac


def build_magic_packet(mac_hex: str) -> bytes:
    mac_bytes = bytes.fromhex(mac_hex)
    return b"\xff" * 6 + mac_bytes * 16


def send_wol(mac_hex: str, broadcast: str, port: int,
             count: int, interval: float) -> None:
    packet = build_magic_packet(mac_hex)
    mac_fmt = ":".join(mac_hex[i:i+2] for i in range(0, 12, 2))

    print(f"  mac addr  : {mac_fmt}")
    print(f"  broadcast : {broadcast}")
    print(f"  port      : {port}")
    print(f"  packets   : {count}  (interval: {interval}s)")
    print()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        for i in range(1, count + 1):
            sock.sendto(packet, (broadcast, port))
            print(f"  [{i}/{count}] sent -> {broadcast}:{port}")
            if i < count and interval > 0:
                time.sleep(interval)
        print("  [+] all packets sent successfully")
    except OSError as exc:
        print(f"  [!] send error: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        sock.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Wake-on-LAN magic packet sender")
    parser.add_argument("--mac", required=True, help="MAC address (AA:BB:CC:DD:EE:FF)")
    parser.add_argument("--broadcast", default="255.255.255.255", help="broadcast address")
    parser.add_argument("--port", type=int, default=9, help="UDP port (default: 9)")
    parser.add_argument("--count", type=int, default=5, help="packet count (default: 5)")
    parser.add_argument("--interval", type=float, default=1.0, help="interval seconds (default: 1.0)")
    args = parser.parse_args()

    try:
        mac = normalize_mac(args.mac)
    except ValueError as e:
        print(f"[!] {e}", file=sys.stderr)
        sys.exit(1)

    print("[*] wake-on-lan")
    print()
    send_wol(mac, args.broadcast, args.port, args.count, args.interval)


if __name__ == "__main__":
    main()
PYEOF
    ok

    step "generating ~/bin/wake-desktop ..."
    # Use the dynamically detected shell and python paths
    ssh_relay "cat > ~/bin/wake-desktop" << WRAPEOF
#!${remote_shell}
exec ${remote_python} ~/tailwake/wake_desktop.py \
    --mac "${DESKTOP_MAC}" \
    --broadcast "${BROADCAST}" \
    --port "${WOL_PORT}" \
    --count 5 \
    --interval 1
WRAPEOF
    ok

    step "chmod +x ~/bin/wake-desktop ..."
    ssh_relay "chmod +x ~/bin/wake-desktop"
    ok

    echo ""
    success "setup complete on relay"
    echo ""
    detail "next steps:"
    detail "./tailwake.sh          — full automation"
    detail "./tailwake.sh doctor   — diagnostics"
}

# ── 8. wake (raw WoL send) ────────────────────────────────────────────────────
cmd_wake() {
    info "preparing wake-on-lan for ${DESKTOP_IP}"
    echo ""

    step "checking ~/bin/wake-desktop on relay ..."
    if ssh_relay "test -x ~/bin/wake-desktop" 2>/dev/null; then
        ok
    else
        fail
        warn "remote script not found, running setup ..."
        echo ""
        cmd_setup
        echo ""
    fi

    info "sending magic packets via relay"
    echo ""
    if ssh_relay "~/bin/wake-desktop"; then
        echo ""
        success "magic packets sent to ${BROADCAST}:${WOL_PORT}"
        detail "MAC: ${DESKTOP_MAC}"
        detail "IP:  ${DESKTOP_IP}"
    else
        echo ""
        error "failed to send magic packet via relay"
        return 1
    fi
}

# ── 9. wake-and-wait ─────────────────────────────────────────────────────────
cmd_wake_and_wait() {
    banner

    # ── 1. Test SSH ──────────────────────────────────────────────────────────
    step "[1/5] checking connection to relay ..."
    if ! ssh_relay "echo alive" >/dev/null 2>&1; then
        fail
        echo ""
        error "relay unreachable. Check if it is on the Tailnet."
        return 1
    fi
    ok

    # ── 2. Check if desktop is already online ────────────────────────────────
    step "[2/5] checking desktop state ..."
    local desktop_online=false
    set +e
    if remote_tcp_check "${SUNSHINE_HOST}" "${SUNSHINE_PORT}" "5" >/dev/null 2>&1; then
        ok
        desktop_online=true
    else
        ok
        desktop_online=false
    fi
    set -e

    if $desktop_online; then
        echo ""
        success "desktop already online with Sunshine ready"
        detail "${SUNSHINE_HOST}:${SUNSHINE_PORT}"
        return 0
    fi
    detail "${DESKTOP_IP} offline — starting wake sequence"
    echo ""

    # ── 3. Ensure setup ──────────────────────────────────────────────────────
    step "[3/5] checking ~/bin/wake-desktop on relay ..."
    if ! ssh_relay "test -x ~/bin/wake-desktop" 2>/dev/null; then
        fail
        echo ""
        info "running setup ..."
        echo ""
        cmd_setup
        echo ""
    else
        ok
    fi

    # ── 4. Send WoL ──────────────────────────────────────────────────────────
    echo ""
    step "[4/5] sending WoL magic packet ..."
    echo ""
    if ! ssh_relay "~/bin/wake-desktop"; then
        echo ""
        error "failed to send magic packet"
        detail "check that relay is on the same physical LAN as the desktop"
        return 1
    fi
    echo ""
    success "magic packets sent to ${BROADCAST}:${WOL_PORT}"

    # ── 5. Boot grace + wait for Sunshine ────────────────────────────────────
    echo ""
    info "[5/5] waiting for Sunshine to be ready"
    echo ""
    detail "boot grace: ${BOOT_GRACE_SECONDS}s before starting checks"
    sleep "${BOOT_GRACE_SECONDS}"
    echo ""

    if wait_for_sunshine; then
        echo ""
        success "Desktop is ready for Moonlight/Sunshine"
        detail "IP:  ${SUNSHINE_HOST}"
        detail "TCP: ${SUNSHINE_PORT}"
        return 0
    else
        echo ""
        warn "WoL packet may have been sent but desktop did not become ready"
        warn "possible causes:"
        detail "  BIOS WoL disabled (Resume PCI-E Device)"
        detail "  Windows Fast Startup enabled"
        detail "  Sunshine not set to autostart"
        detail "  Windows Firewall blocking port ${SUNSHINE_PORT}"
        detail "  Relay and desktop not on same physical LAN?"
        echo ""
        detail "try: ./tailwake.sh doctor"
        return 1
    fi
}

# ── 10. status ───────────────────────────────────────────────────────────────
cmd_status() {
    info "detailed status"
    echo ""

    # Relay SSH
    printf "  ${CYAN}Relay SSH${NC}  ${DIM}@${NC} ${SSH_TARGET}:${RELAY_PORT}  ... "
    if ssh_relay "echo alive" >/dev/null 2>&1; then
        printf "${GREEN}OK${NC}\n"
    else
        printf "${RED}FAIL${NC}\n"
        error "relay unreachable"
        return 1
    fi

    # Desktop ping (best-effort)
    printf "  ${CYAN}Desktop ping${NC} ${DIM}@${NC} ${DESKTOP_IP}  ... "
    set +e
    local ping_ok=false
    if ssh_relay "ping -c 1 -W 3 ${DESKTOP_IP} 2>/dev/null" >/dev/null 2>&1; then
        printf "${GREEN}OK${NC}\n"
        ping_ok=true
    elif ssh_relay "ping -c 1 -W 3 ${DESKTOP_IP} 2>&1" | grep -qi "not found\|permission\|prohibited" >/dev/null 2>&1; then
        printf "${YELLOW}UNKNOWN${NC} ${DIM}(ping not available on relay)${NC}\n"
    else
        printf "${RED}FAIL${NC}\n"
    fi
    set -e

    # Sunshine TCP
    printf "  ${CYAN}Sunshine TCP${NC} ${DIM}@${NC} ${SUNSHINE_HOST}:${SUNSHINE_PORT} ... "
    set +e
    local sunshine_ok=false
    if check_sunshine >/dev/null 2>&1; then
        printf "${GREEN}OK${NC}\n"
        sunshine_ok=true
    else
        printf "${RED}FAIL${NC}\n"
    fi
    set -e

    echo ""
    if $sunshine_ok; then
        success "desktop ready for Moonlight/Sunshine"
    elif $ping_ok; then
        warn "desktop online but Sunshine not responding"
        detail "check if Sunshine is running and firewall is not blocking port ${SUNSHINE_PORT}"
    else
        warn "desktop offline"
        detail "to turn on: ./tailwake.sh"
    fi
}

# ── 11. doctor ────────────────────────────────────────────────────────────────
cmd_doctor() {
    banner
    info "running diagnostics"
    echo ""

    detail "RELAY_USER:       ${RELAY_USER}"
    detail "RELAY_HOST:       ${RELAY_HOST}"
    detail "RELAY_PORT:       ${RELAY_PORT}"
    detail "DESKTOP_MAC:      ${DESKTOP_MAC}"
    detail "DESKTOP_IP:       ${DESKTOP_IP}"
    detail "BROADCAST:        ${BROADCAST}"
    detail "WOL_PORT:         ${WOL_PORT}"
    detail "SUNSHINE_HOST:    ${SUNSHINE_HOST}"
    detail "SUNSHINE_PORT:    ${SUNSHINE_PORT}"
    detail "WAIT_TIMEOUT:     ${WAIT_TIMEOUT}s"
    detail "WAIT_INTERVAL:    ${WAIT_INTERVAL}s"
    detail "BOOT_GRACE:       ${BOOT_GRACE_SECONDS}s"
    echo ""

    # SSH
    step "[1/6] SSH to ${SSH_TARGET} ..."
    if ssh_relay "echo connected" >/dev/null 2>&1; then
        ok
    else
        fail
        error "  SSH failed. Check:"
        detail "  relay powered on and on Tailnet?"
        detail "  sshd running on relay (port ${RELAY_PORT})?"
        detail "  ssh -p ${RELAY_PORT} ${SSH_TARGET}"
    fi
    echo ""

    # Python
    step "[2/6] Python on relay ..."
    if ssh_relay "command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1" >/dev/null 2>&1; then
        ok
    else
        fail
        warn "  Python not found"
        detail "  run: ./tailwake.sh setup"
    fi
    echo ""

    # Wrapper
    step "[3/6] ~/bin/wake-desktop ..."
    if ssh_relay "test -x ~/bin/wake-desktop" >/dev/null 2>&1; then
        ok
    else
        fail
        warn "  wrapper not found"
        detail "  run: ./tailwake.sh setup"
    fi
    echo ""

    # TCP check helper
    step "[4/6] remote_tcp_check (inline Python) ..."
    if remote_tcp_check "${SUNSHINE_HOST}" "${SUNSHINE_PORT}" "5" >/dev/null 2>&1; then
        ok
    else
        # May fail if desktop is offline — test against the relay's own SSH port
        if remote_tcp_check "${RELAY_HOST}" "${RELAY_PORT}" "3" >/dev/null 2>&1; then
            ok
            detail "TCP check works (tested against relay SSH port)"
        else
            fail
            warn "  TCP check helper failed"
            detail "  Python on relay may be incomplete"
        fi
    fi
    echo ""

    # Sunshine check
    step "[5/6] Sunshine ${SUNSHINE_HOST}:${SUNSHINE_PORT} ..."
    set +e
    if check_sunshine >/dev/null 2>&1; then
        ok
        success "  Sunshine ready"
    else
        fail
        warn "  Sunshine not ready (desktop may be offline)"
    fi
    set -e
    echo ""

    # Ping desktop
    step "[6/6] ping desktop ${DESKTOP_IP} ..."
    set +e
    if ssh_relay "ping -c 1 -W 2 ${DESKTOP_IP} 2>/dev/null" >/dev/null 2>&1; then
        ok
    else
        fail
        detail "  desktop offline or ping not available on relay"
    fi
    set -e
    echo ""

    # Summary
    info "---"
    echo ""
    if ssh_relay "echo ok" >/dev/null 2>&1 \
        && ssh_relay "command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1" >/dev/null 2>&1 \
        && ssh_relay "test -x ~/bin/wake-desktop" >/dev/null 2>&1; then
        success "system ready — ./tailwake.sh to turn on"
    else
        warn "there are pending issues (see above)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    local cmd="${1:-auto}"
    local config_path=""

    # Parse --config before anything else
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                shift
                config_path="$1"
                shift
                ;;
            *)
                # First non-flag argument is the command — stop parsing flags
                if [[ "$1" != -* ]]; then
                    cmd="$1"
                    shift
                else
                    shift
                fi
                ;;
        esac
    done

    # Load configuration
    local config_loaded=false

    if [[ -n "$config_path" ]]; then
        if load_config "$config_path"; then
            config_loaded=true
        else
            error "config file not found: ${config_path}"
            exit 1
        fi
    fi

    if ! $config_loaded && [[ -f "./tailwake.env" ]]; then
        load_config "./tailwake.env" && config_loaded=true
    fi

    if ! $config_loaded && [[ -f "${HOME}/.config/tailwake/tailwake.env" ]]; then
        load_config "${HOME}/.config/tailwake/tailwake.env" && config_loaded=true
    fi

    # For commands that need config, validate
    case "${cmd}" in
        help|--help|-h)
            usage
            exit 0
            ;;
    esac

    if ! $config_loaded; then
        error "Config file not found."
        echo ""
        detail "Copy tailwake.env.example to tailwake.env and edit it:"
        detail "  cp tailwake.env.example tailwake.env"
        detail "  vim tailwake.env"
        echo ""
        detail "Or place it at ~/.config/tailwake/tailwake.env"
        echo ""
        detail "You can also pass a custom path:"
        detail "  ./tailwake.sh --config /path/to/config.env doctor"
        exit 1
    fi

    # Build SSH command from loaded config
    build_ssh_cmd

    case "${cmd}" in
        auto|wake-and-wait)
            cmd_wake_and_wait
            ;;
        help|--help|-h)
            usage
            ;;
        test-ssh)
            cmd_test_ssh
            ;;
        setup)
            cmd_setup
            ;;
        wake)
            cmd_wake
            ;;
        wait)
            wait_for_sunshine
            ;;
        sunshine)
            cmd_sunshine
            ;;
        status)
            cmd_status
            ;;
        doctor)
            cmd_doctor
            ;;
        *)
            error "unknown command: ${cmd}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
