#!/bin/bash
# Batocera WebDashboard PRO — Unified Installer v2.0
# Usage:
#   ./install.sh                  Interactive guided install
#   ./install.sh --unattended     Non-interactive (ENV vars or defaults)
#   ./install.sh --update         Update to latest version
#   ./install.sh --uninstall      Remove installation
#   ./install.sh --status         Show current status
#   ./install.sh --config FILE    Load config from file

set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT=8989
NATIVE_INSTALL_DIR="/userdata/system/interface-pro"
NATIVE_CUSTOM_SH="/userdata/system/custom.sh"
CONFIG_FILE=""
UNATTENDED=false
MODE=""       # remote | native — set by ENV or user input
BATOCERA_HOST="${BATOCERA_HOST:-}"
BATOCERA_USER="${BATOCERA_USER:-root}"
BATOCERA_PASS="${BATOCERA_PASS:-linux}"
PORT="${PORT:-$DEFAULT_PORT}"

# ─── Parse flags ───────────────────────────────────────────────────────────────
COMMAND="install"
for arg in "$@"; do
    case "$arg" in
        --unattended) UNATTENDED=true ;;
        --update)     COMMAND="update" ;;
        --uninstall)  COMMAND="uninstall" ;;
        --status)     COMMAND="status" ;;
        --config)     ;;  # handled below
    esac
done

# Handle --config FILE
for i in "$@"; do
    if [ "$i" = "--config" ]; then
        shift_next=true
    elif [ "${shift_next:-false}" = true ]; then
        CONFIG_FILE="$i"
        shift_next=false
    fi
done

if [ -n "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        BATOCERA_HOST="${HOST:-$BATOCERA_HOST}"
        BATOCERA_USER="${USER:-$BATOCERA_USER}"
        BATOCERA_PASS="${PASS:-$BATOCERA_PASS}"
        PORT="${PORT:-$DEFAULT_PORT}"
        MODE="${MODE:-${BATOCERA_MODE:-}}"
        [ "${AUTO_START:-}" = "yes" ] && UNATTENDED=true
    else
        echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
fi

# ENV override for unattended mode
[ -n "${BATOCERA_MODE:-}" ] && MODE="$BATOCERA_MODE"

# ─── Banner ────────────────────────────────────────────────────────────────────
print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║       Batocera WebDashboard PRO — Installer v2.0             ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─── OS Detection ──────────────────────────────────────────────────────────────
detect_os() {
    if [ -d "/userdata/system" ] && grep -q "batocera" /etc/os-release 2>/dev/null; then
        echo "batocera"
    elif [ "$(uname -s)" = "Darwin" ]; then
        echo "macos"
    elif [ "$(uname -s)" = "Linux" ]; then
        # Detect WSL
        if grep -qi "microsoft" /proc/version 2>/dev/null; then
            echo "wsl"
        else
            echo "linux"
        fi
    else
        local u
        u="$(uname -s 2>/dev/null || echo '')"
        case "$u" in
            CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
            *) echo "unknown" ;;
        esac
    fi
}

# ─── Port Utilities ────────────────────────────────────────────────────────────
check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || \
       ss -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1  # in use
    fi
    return 0
}

find_free_port() {
    local port=$1
    while ! check_port "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

resolve_port() {
    local requested_port=$1
    if ! check_port "$requested_port"; then
        local suggested
        suggested=$(find_free_port "$requested_port")
        echo ""
        echo -e "${YELLOW}  ⚠️  Port ${requested_port} is already in use!${NC}"
        echo -e "     Suggested free port: ${GREEN}${suggested}${NC}"
        echo ""
        if [ "$UNATTENDED" = true ]; then
            echo -e "     ${CYAN}[Unattended] Using port ${suggested}${NC}"
            PORT="$suggested"
        else
            read -rp "     Accept [$suggested] or enter custom port: " user_port
            PORT="${user_port:-$suggested}"
        fi
    else
        PORT="$requested_port"
    fi
}

# ─── Mode Explanation ──────────────────────────────────────────────────────────
show_mode_explanation() {
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════════╗"
    echo    "  ║           🌐 REMOTE MODE (on Mac/PC/Server)                   ║"
    echo    "  ║                                                                ║"
    echo    "  ║  • Dashboard runs on YOUR MACHINE (Mac/PC/Server)              ║"
    echo    "  ║  • Connects via SSH to your Batocera                           ║"
    echo    "  ║  • Batocera only needs SSH (port 22)                           ║"
    echo    "  ║  • Best for: Batocera on weak hardware                         ║"
    echo    "  ║                                                                ║"
    echo -e "  ║  URL after start: http://localhost:PORT                        ║"
    echo    "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "  ╔══════════════════════════════════════════════════════════════╗"
    echo    "  ║           🎮 NATIVE MODE (directly on Batocera)              ║"
    echo    "  ║                                                                ║"
    echo    "  ║  • Dashboard runs DIRECTLY on your Batocera device            ║"
    echo    "  ║  • No SSH needed, no second computer needed                   ║"
    echo    "  ║  • Starts AUTOMATICALLY when Batocera boots                   ║"
    echo    "  ║  • Best for: stationary Batocera, always-on access            ║"
    echo    "  ║                                                                ║"
    echo -e "  ║  URL after start: http://batocera.local:8989                  ║"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}  💡 Both modes can be installed from your Mac/PC.${NC}"
    echo -e "${YELLOW}     For Native, you'll be asked for your Batocera SSH details${NC}"
    echo -e "${YELLOW}     so the dashboard can be pushed to your device automatically.${NC}"
    echo ""
}

# ─── Mode Selection ────────────────────────────────────────────────────────────
select_mode() {
    local detected_os=$1

    # If running directly on Batocera, default to native
    if [ "$detected_os" = "batocera" ] && [ -z "$MODE" ]; then
        if [ "$UNATTENDED" = true ]; then
            MODE="native"
            return
        fi
        echo -e "${YELLOW}  Batocera detected! Defaulting to Native Mode.${NC}"
        echo ""
        read -rp "  Install in Native Mode? [Y/n]: " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            MODE="native"
            return
        fi
    fi

    if [ -n "$MODE" ]; then
        return
    fi

    show_mode_explanation

    echo -e "${BOLD}  Which installation mode do you want?${NC}"
    echo ""
    echo "    [1] 🌐 REMOTE   — I run this on my Mac/PC (NOT on Batocera)"
    echo "    [2] 🎮 NATIVE   — I run this DIRECTLY on my Batocera"
    echo ""
    read -rp "  Enter choice [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        2) MODE="native" ;;
        *) MODE="remote" ;;
    esac
}

# ─── Windows / WSL Notice ──────────────────────────────────────────────────────
show_windows_notes() {
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗"
    echo    "  ║  💡 WINDOWS NOTES                                         ║"
    echo    "  ║                                                            ║"
    echo    "  ║  This script runs via WSL (recommended) or Git Bash.      ║"
    echo    "  ║  You can open WSL Terminal with: Ctrl+Shift+2 in Files    ║"
    echo    "  ║                                                            ║"
    echo    "  ║  For WSL setup:                                            ║"
    echo    "  ║    https://docs.microsoft.com/en-us/windows/wsl/install    ║"
    echo -e "  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─── Remote Installation ───────────────────────────────────────────────────────
install_remote() {
    echo -e "${CYAN}  ── Remote Mode Setup ──────────────────────────────────────────${NC}"
    echo ""

    # Collect SSH credentials
    if [ "$UNATTENDED" = true ]; then
        if [ -z "$BATOCERA_HOST" ]; then
            echo -e "${RED}  Error: BATOCERA_HOST is required for unattended remote install.${NC}"
            echo "  Set: export BATOCERA_HOST=<ip>"
            exit 1
        fi
    else
        # Interactive — but skip if already have a .env
        if [ -f "$SCRIPT_DIR/.env" ]; then
            echo -e "${YELLOW}  Existing configuration found (.env). Using it.${NC}"
            echo -e "  (Delete .env to reconfigure.)"
            # Load existing
            # shellcheck disable=SC1090
            source "$SCRIPT_DIR/.env" 2>/dev/null || true
            PORT="${PORT:-$DEFAULT_PORT}"
        else
            read -rp "  Enter Batocera IP or hostname: " BATOCERA_HOST
            read -rp "  Enter Batocera username [root]: " BATOCERA_USER
            BATOCERA_USER="${BATOCERA_USER:-root}"
            read -rsp "  Enter Batocera password [linux]: " BATOCERA_PASS
            echo ""
            BATOCERA_PASS="${BATOCERA_PASS:-linux}"
            read -rp "  Enter Web UI port [$DEFAULT_PORT]: " input_port
            PORT="${input_port:-$DEFAULT_PORT}"
        fi
    fi

    # Port conflict check
    resolve_port "$PORT"

    # Check Python
    echo ""
    echo -e "${YELLOW}  [1/3] Checking Python...${NC}"
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}  Error: Python 3 is required but not installed.${NC}"
        exit 1
    fi
    local py_version
    py_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local py_major py_minor
    py_major=$(echo "$py_version" | cut -d. -f1)
    py_minor=$(echo "$py_version" | cut -d. -f2)
    echo -e "${GREEN}  ✅ Python ${py_version} found${NC}"
    if [ "$py_major" -lt 3 ] || { [ "$py_major" -eq 3 ] && [ "$py_minor" -lt 10 ]; }; then
        echo -e "${YELLOW}  ⚠️  Python 3.10+ recommended. Some dependencies may not install.${NC}"
    fi

    # Virtual environment
    echo -e "${YELLOW}  [2/3] Setting up virtual environment...${NC}"
    if [ ! -d "$SCRIPT_DIR/.venv" ]; then
        python3 -m venv "$SCRIPT_DIR/.venv"
        echo -e "${GREEN}  ✅ Virtual environment created${NC}"
    else
        echo -e "${CYAN}  ℹ  Virtual environment already exists${NC}"
    fi
    "$SCRIPT_DIR/.venv/bin/pip" install --upgrade pip -q
    if "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q 2>/dev/null; then
        echo -e "${GREEN}  ✅ Dependencies installed${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Some dependencies failed. Trying without version pins...${NC}"
        "$SCRIPT_DIR/.venv/bin/pip" install flask paramiko python-dotenv -q \
            && echo -e "${GREEN}  ✅ Core dependencies installed${NC}" \
            || { echo -e "${RED}  Error: Could not install required packages.${NC}"; exit 1; }
    fi

    # Write .env
    echo -e "${YELLOW}  [3/3] Writing configuration...${NC}"
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        cat > "$SCRIPT_DIR/.env" <<EOF
BATOCERA_HOST=${BATOCERA_HOST}
BATOCERA_USER=${BATOCERA_USER}
BATOCERA_PASS=${BATOCERA_PASS}
PORT=${PORT}
EOF
        echo -e "${GREEN}  ✅ Configuration saved to .env${NC}"
    else
        # Update PORT in existing .env if it changed
        if grep -q "^PORT=" "$SCRIPT_DIR/.env"; then
            sed -i.bak "s/^PORT=.*/PORT=${PORT}/" "$SCRIPT_DIR/.env" && rm -f "$SCRIPT_DIR/.env.bak"
        fi
        echo -e "${CYAN}  ℹ  Configuration already exists (preserved)${NC}"
    fi

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════════╗"
    echo    "  ║  ✅ Remote installation complete!                              ║"
    echo    "  ║                                                                ║"
    printf  "  ║  Start dashboard:  ./install.sh --status                       ║\n"
    echo    "  ║  Or run directly:  .venv/bin/python3 server.py                 ║"
    printf  "  ║  URL:              http://localhost:%s                          ║\n" "$PORT"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Auto-start?
    if [ "$UNATTENDED" = false ]; then
        read -rp "  Start the dashboard now? [Y/n]: " start_now
        start_now="${start_now:-Y}"
        if [[ "$start_now" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${CYAN}  Starting Batocera WebDashboard PRO...${NC}"
            echo -e "${CYAN}  Press Ctrl+C to stop.${NC}"
            echo ""
            cd "$SCRIPT_DIR" && "$SCRIPT_DIR/.venv/bin/python3" server.py
        fi
    fi
}

# ─── Native: Auto-detect (local vs SSH-push) ───────────────────────────────────
install_native() {
    echo -e "${CYAN}  ── Native Mode Setup ──────────────────────────────────────────${NC}"
    echo ""

    # Are we on Batocera ourselves?
    if [ -d "/userdata/system" ] && grep -q "batocera" /etc/os-release 2>/dev/null; then
        echo -e "${GREEN}  ✅ Running on Batocera — installing locally.${NC}"
        install_native_local
    else
        echo -e "${CYAN}  You're not on Batocera — Native Mode will be installed${NC}"
        echo -e "${CYAN}  on your Batocera device over SSH.${NC}"
        echo ""
        install_native_via_ssh
    fi
}

# ─── Native: Local install (running on Batocera) ───────────────────────────────
install_native_local() {
    # Determine source dir
    local src_dir="$SCRIPT_DIR/batocera-native"
    if [ ! -d "$src_dir" ]; then
        # If already running from inside batocera-native
        src_dir="$SCRIPT_DIR"
    fi

    # Port
    if [ "$UNATTENDED" = false ]; then
        read -rp "  Enter Web UI port [$DEFAULT_PORT]: " input_port
        PORT="${input_port:-$DEFAULT_PORT}"
    fi
    resolve_port "$PORT"

    echo -e "${YELLOW}  [1/4] Creating installation directory...${NC}"
    mkdir -p "$NATIVE_INSTALL_DIR"
    echo -e "${GREEN}  ✅ $NATIVE_INSTALL_DIR ready${NC}"

    echo -e "${YELLOW}  [2/4] Deploying files...${NC}"
    if [ "$src_dir" != "$NATIVE_INSTALL_DIR" ]; then
        cp -r "$src_dir"/. "$NATIVE_INSTALL_DIR/"
        echo -e "${GREEN}  ✅ Files deployed${NC}"
    else
        echo -e "${CYAN}  ℹ  Already in install directory${NC}"
    fi

    echo -e "${YELLOW}  [3/4] Installing Flask...${NC}"
    local python_exec="python3"
    if pip3 install flask --user -q 2>/dev/null; then
        python_exec="python3"
        echo -e "${GREEN}  ✅ Flask installed (system pip)${NC}"
    else
        python3 -m venv "$NATIVE_INSTALL_DIR/.venv"
        "$NATIVE_INSTALL_DIR/.venv/bin/pip" install flask -q
        python_exec="$NATIVE_INSTALL_DIR/.venv/bin/python3"
        echo -e "${GREEN}  ✅ Flask installed (venv)${NC}"
    fi

    echo -e "${YELLOW}  [4/4] Configuring autostart...${NC}"
    write_start_script_local "$python_exec"
    register_custom_sh_local

    batocera-save-overlay &>/dev/null || true

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║  ✅ Native installation complete!                              ║"
    echo -e "  ║                                                                ║"
    echo -e "  ║  The dashboard starts automatically on next boot.              ║"
    printf "  ║  URL: http://batocera.local:%-34s ║\n" "$PORT"
    echo -e "  ║                                                                ║"
    echo -e "  ║  Reboot to activate, or start manually:                        ║"
    echo -e "  ║    $NATIVE_INSTALL_DIR/start_native.sh"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

write_start_script_local() {
    local python_exec="$1"
    local start_script="$NATIVE_INSTALL_DIR/start_native.sh"
    cat > "$start_script" <<STARTEOF
#!/bin/bash
exec > "$NATIVE_INSTALL_DIR/boot.log" 2>&1
echo "Starting Batocera WebDashboard PRO at \$(date)"
sleep 15
cd "$NATIVE_INSTALL_DIR"
PORT=$PORT $python_exec server.py
STARTEOF
    chmod +x "$start_script"
}

register_custom_sh_local() {
    if [ ! -f "$NATIVE_CUSTOM_SH" ]; then
        echo "#!/bin/bash" > "$NATIVE_CUSTOM_SH"
    fi
    sed -i '/interface-pro/d' "$NATIVE_CUSTOM_SH"
    {
        echo ""
        echo "# Start Batocera WebDashboard PRO"
        echo "$NATIVE_INSTALL_DIR/start_native.sh &"
    } >> "$NATIVE_CUSTOM_SH"
    chmod +x "$NATIVE_CUSTOM_SH"
}

# ─── Native: SSH push install (from Mac/PC to Batocera) ────────────────────────
install_native_via_ssh() {
    # Source dir for batocera-native files
    local src_dir="$SCRIPT_DIR/batocera-native"
    if [ ! -d "$src_dir" ]; then
        echo -e "${RED}  Error: $src_dir not found.${NC}"
        echo "  This installer needs to be run from the project root."
        exit 1
    fi

    # Collect SSH details
    if [ "$UNATTENDED" = true ]; then
        if [ -z "$BATOCERA_HOST" ]; then
            echo -e "${RED}  Error: BATOCERA_HOST is required for unattended SSH install.${NC}"
            echo "  Set: export BATOCERA_HOST=<ip>"
            exit 1
        fi
    else
        echo -e "${BOLD}  SSH connection to Batocera${NC}"
        echo -e "  ${CYAN}(Tip: enable SSH in Batocera under Network Settings → Enable SSH)${NC}"
        echo ""
        local default_host="${BATOCERA_HOST:-batocera.local}"
        read -rp "  Batocera IP or hostname [$default_host]: " input_host
        BATOCERA_HOST="${input_host:-$default_host}"
        read -rp "  SSH user [root]: " input_user
        BATOCERA_USER="${input_user:-root}"
        read -rp "  Web UI port [$DEFAULT_PORT]: " input_port
        PORT="${input_port:-$DEFAULT_PORT}"
    fi

    # Test SSH connection + verify Batocera
    echo ""
    echo -e "${YELLOW}  [1/6] Testing SSH connection to ${BATOCERA_USER}@${BATOCERA_HOST}...${NC}"
    echo -e "  ${CYAN}(You may be prompted for the SSH password — default is 'linux')${NC}"

    # Use a control socket so user only types the password ONCE for this session
    local SSH_SOCKET
    SSH_SOCKET="$(mktemp -u -t bdspro-ssh-XXXXXX 2>/dev/null || mktemp -u /tmp/bdspro-ssh-XXXXXX)"

    # Open master connection (interactive password prompt happens here)
    if ! ssh -M -S "$SSH_SOCKET" -fN \
            -o ControlPersist=600 \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=15 \
            "${BATOCERA_USER}@${BATOCERA_HOST}" 2>&1; then
        echo ""
        echo -e "${RED}  ❌ SSH connection failed.${NC}"
        echo ""
        echo "  Common causes:"
        echo "   • SSH not enabled on Batocera (Settings → Network → Enable SSH)"
        echo "   • Wrong IP/hostname (check with 'arp -a' or your router)"
        echo "   • Batocera not on the same network or powered off"
        echo "   • Firewall blocking port 22"
        exit 1
    fi

    # Helper for running commands via the socket
    _ssh_run()  { ssh -S "$SSH_SOCKET" "${BATOCERA_USER}@${BATOCERA_HOST}" "$@"; }
    _scp_to()   { scp -o ControlPath="$SSH_SOCKET" -r "$@" "${BATOCERA_USER}@${BATOCERA_HOST}:$NATIVE_INSTALL_DIR/"; }
    _ssh_close(){ ssh -S "$SSH_SOCKET" -O exit "${BATOCERA_USER}@${BATOCERA_HOST}" 2>/dev/null || true; }
    trap _ssh_close EXIT

    if _ssh_run "test -d /userdata/system && grep -q batocera /etc/os-release 2>/dev/null"; then
        echo -e "${GREEN}  ✅ Connected — confirmed Batocera system.${NC}"
    else
        echo -e "${RED}  ❌ Connected, but this doesn't look like Batocera (/userdata/system not found).${NC}"
        echo "  Are you sure this is your Batocera device?"
        exit 1
    fi

    # Show remote Batocera version for confidence
    local remote_ver
    remote_ver=$(_ssh_run "batocera-version 2>/dev/null || cat /usr/share/batocera/batocera.version 2>/dev/null || echo unknown" | tr -d '\r\n')
    echo -e "  ${CYAN}Remote: ${remote_ver}${NC}"

    # 2. Prepare install dir (handle existing installation)
    echo -e "${YELLOW}  [2/6] Preparing $NATIVE_INSTALL_DIR on Batocera...${NC}"
    if _ssh_run "test -d $NATIVE_INSTALL_DIR"; then
        if [ "$UNATTENDED" = false ]; then
            echo -e "${YELLOW}  ⚠️  Existing installation found at $NATIVE_INSTALL_DIR${NC}"
            read -rp "     Overwrite? [Y/n]: " ow
            ow="${ow:-Y}"
            [[ "$ow" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }
        fi
        # Stop running server before overwriting
        _ssh_run "pkill -f 'server.py' 2>/dev/null; rm -rf $NATIVE_INSTALL_DIR" || true
    fi
    _ssh_run "mkdir -p $NATIVE_INSTALL_DIR"
    echo -e "${GREEN}  ✅ Install directory ready${NC}"

    # 3. Copy files
    echo -e "${YELLOW}  [3/6] Copying files to Batocera...${NC}"
    if ! _scp_to "$src_dir"/.; then
        echo -e "${RED}  ❌ File transfer failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✅ Files transferred${NC}"

    # 4. Install Flask on remote
    echo -e "${YELLOW}  [4/6] Installing Flask on Batocera...${NC}"
    local remote_python_exec
    if _ssh_run "pip3 install flask --user -q 2>/dev/null"; then
        remote_python_exec="python3"
        echo -e "${GREEN}  ✅ Flask installed (system pip)${NC}"
    elif _ssh_run "python3 -m venv $NATIVE_INSTALL_DIR/.venv && $NATIVE_INSTALL_DIR/.venv/bin/pip install flask -q"; then
        remote_python_exec="$NATIVE_INSTALL_DIR/.venv/bin/python3"
        echo -e "${GREEN}  ✅ Flask installed (venv)${NC}"
    else
        echo -e "${RED}  ❌ Could not install Flask.${NC}"
        echo "  Try connecting via SSH manually and running: pip3 install flask --user"
        exit 1
    fi

    # 5. Write start_native.sh locally with substituted values, then push
    echo -e "${YELLOW}  [5/6] Writing autostart script...${NC}"
    local tmp_start
    tmp_start="$(mktemp -t bdspro-start-XXXXXX 2>/dev/null || mktemp /tmp/bdspro-start-XXXXXX)"
    cat > "$tmp_start" <<STARTEOF
#!/bin/bash
exec > "$NATIVE_INSTALL_DIR/boot.log" 2>&1
echo "Starting Batocera WebDashboard PRO at \$(date)"
sleep 15
cd "$NATIVE_INSTALL_DIR"
PORT=$PORT $remote_python_exec server.py
STARTEOF
    scp -o ControlPath="$SSH_SOCKET" "$tmp_start" \
        "${BATOCERA_USER}@${BATOCERA_HOST}:$NATIVE_INSTALL_DIR/start_native.sh"
    rm -f "$tmp_start"
    _ssh_run "chmod +x $NATIVE_INSTALL_DIR/start_native.sh"
    echo -e "${GREEN}  ✅ Autostart script installed${NC}"

    # 6. Register in custom.sh + save overlay
    echo -e "${YELLOW}  [6/6] Registering in custom.sh + saving overlay...${NC}"
    _ssh_run "
        if [ ! -f $NATIVE_CUSTOM_SH ]; then
            echo '#!/bin/bash' > $NATIVE_CUSTOM_SH
        fi
        sed -i '/interface-pro/d' $NATIVE_CUSTOM_SH
        {
            echo ''
            echo '# Start Batocera WebDashboard PRO'
            echo '$NATIVE_INSTALL_DIR/start_native.sh &'
        } >> $NATIVE_CUSTOM_SH
        chmod +x $NATIVE_CUSTOM_SH
        batocera-save-overlay 2>/dev/null || true
    "
    echo -e "${GREEN}  ✅ Autostart configured${NC}"

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║  ✅ Native install pushed to Batocera!                         ║"
    echo -e "  ║                                                                ║"
    echo -e "  ║  Auto-starts on next boot.                                     ║"
    printf "  ║  URL: %-55s ║\n" "http://${BATOCERA_HOST}:${PORT}"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Offer to start immediately
    if [ "$UNATTENDED" = false ]; then
        read -rp "  Start the dashboard now (no need to reboot)? [Y/n]: " start_now
        start_now="${start_now:-Y}"
        if [[ "$start_now" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}  Starting via SSH (the start script waits 15 s for boot to settle)...${NC}"
            # Launch in the background; start_native.sh has its own sleep 15 before
            # it actually starts the server (so the dashboard is ready ~17 s later).
            _ssh_run "nohup $NATIVE_INSTALL_DIR/start_native.sh >/dev/null 2>&1 &"
            # Poll for up to 30 s — print a dot every 2 s so the user sees progress
            local up=false
            printf "  Waiting for HTTP response"
            for _ in $(seq 1 15); do
                sleep 2
                if curl -sf --max-time 2 "http://${BATOCERA_HOST}:${PORT}/health" >/dev/null 2>&1; then
                    up=true
                    break
                fi
                printf "."
            done
            echo ""
            if [ "$up" = true ]; then
                echo -e "${GREEN}  ✅ Dashboard is live at http://${BATOCERA_HOST}:${PORT}${NC}"
            else
                echo -e "${YELLOW}  ⚠️  No HTTP response yet — the server may still be starting. Check:${NC}"
                echo -e "       ssh ${BATOCERA_USER}@${BATOCERA_HOST} 'cat $NATIVE_INSTALL_DIR/boot.log'"
                echo -e "       Or just wait ~20 s and try http://${BATOCERA_HOST}:${PORT} in your browser."
            fi
        fi
    fi

    _ssh_close
    trap - EXIT
}

# ─── Version Check ─────────────────────────────────────────────────────────────
check_for_updates() {
    local current
    current=$(cat "$SCRIPT_DIR/version.txt" 2>/dev/null || echo "0")
    local remote
    remote=$(curl -sf --max-time 5 \
        "https://raw.githubusercontent.com/DavidSchuchert/Batocera-WebDashboard-Pro/main/version.txt" \
        2>/dev/null || echo "")

    if [ -z "$remote" ]; then
        echo -e "${YELLOW}  ⚠️  Could not check for updates (no internet?)${NC}"
        return 2
    fi
    remote=$(echo "$remote" | tr -d '[:space:]')
    current=$(echo "$current" | tr -d '[:space:]')

    if [ "$current" = "$remote" ]; then
        echo -e "${GREEN}  ✅ Already on latest version: ${current}${NC}"
        return 0
    else
        echo -e "${CYAN}  📦 Update available: ${current} → ${remote}${NC}"
        return 1
    fi
}

# ─── Update — Remote Mode ───────────────────────────────────────────────────────
do_update_remote() {
    echo -e "${CYAN}  🔄 Updating Batocera WebDashboard PRO (Remote Mode)...${NC}"
    echo ""

    if ! command -v git &>/dev/null; then
        echo -e "${RED}  Error: git is required for updates.${NC}"
        exit 1
    fi

    # Backup .env
    if [ -f "$SCRIPT_DIR/.env" ]; then
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.backup"
        echo -e "${GREEN}  ✅ Config backed up to .env.backup${NC}"
    fi

    # Pull latest
    cd "$SCRIPT_DIR"
    git stash 2>/dev/null || true
    git pull origin main

    # Restore config
    if [ -f "$SCRIPT_DIR/.env.backup" ]; then
        mv "$SCRIPT_DIR/.env.backup" "$SCRIPT_DIR/.env"
        echo -e "${GREEN}  ✅ SSH credentials restored from backup${NC}"
    fi

    # Update deps
    if [ -d "$SCRIPT_DIR/.venv" ]; then
        "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt" -q 2>/dev/null || \
            "$SCRIPT_DIR/.venv/bin/pip" install flask paramiko python-dotenv -q
        echo -e "${GREEN}  ✅ Dependencies updated${NC}"
    fi

    echo ""
    echo -e "${GREEN}  ✅ Update complete!${NC}"
    echo "  Restart dashboard to apply changes."
}

# ─── Update — Native Mode ───────────────────────────────────────────────────────
do_update_native() {
    echo -e "${CYAN}  🔄 Updating Batocera WebDashboard PRO (Native Mode)...${NC}"
    echo ""

    if [ ! -d "$NATIVE_INSTALL_DIR" ]; then
        echo -e "${RED}  Error: Native installation not found at $NATIVE_INSTALL_DIR${NC}"
        echo "  Run ./install.sh first."
        exit 1
    fi

    cd "$NATIVE_INSTALL_DIR"

    # Backup config
    [ -f ".env" ] && cp ".env" ".env.backup"
    echo -e "${GREEN}  ✅ Config backed up${NC}"

    # Pull latest
    git stash 2>/dev/null || true
    git pull origin main

    # Restore config
    [ -f ".env.backup" ] && mv ".env.backup" ".env"
    echo -e "${GREEN}  ✅ Credentials restored${NC}"

    # Restart service
    pkill -f "server.py" 2>/dev/null || true
    sleep 2
    local start_script="$NATIVE_INSTALL_DIR/start_native.sh"
    if [ -f "$start_script" ]; then
        nohup "$start_script" &>/dev/null &
        echo -e "${GREEN}  ✅ Dashboard restarting...${NC}"
    fi

    batocera-save-overlay &>/dev/null || true

    echo ""
    echo -e "${GREEN}  ✅ Update complete!${NC}"
}

# ─── Update (detect mode & dispatch) ───────────────────────────────────────────
cmd_update() {
    local os
    os=$(detect_os)

    set +e
    check_for_updates
    local update_status=$?
    set -e

    if [ "$update_status" -eq 0 ] && [ "$UNATTENDED" = false ]; then
        read -rp "  Already up to date. Force update anyway? [y/N]: " force
        force="${force:-N}"
        [[ "$force" =~ ^[Yy]$ ]] || exit 0
    fi

    if [ "$os" = "batocera" ] || [ "$MODE" = "native" ]; then
        do_update_native
    else
        do_update_remote
    fi
}

# ─── Existing Install Detection & v1→v2 Migration ──────────────────────────────
migrate_from_v1_remote() {
    echo ""
    echo -e "${CYAN}  📦 Migrating v1.0 Remote installation...${NC}"

    local backup_dir="$SCRIPT_DIR/backup-v1-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    # Backup everything except .git and .venv
    find "$SCRIPT_DIR" -maxdepth 1 \
        ! -name ".git" ! -name ".venv" ! -name "backup-v1*" \
        -exec cp -r {} "$backup_dir/" \; 2>/dev/null || true
    echo -e "${GREEN}  ✅ Backup created: $backup_dir/${NC}"
    echo -e "${GREEN}  ✅ SSH credentials preserved (.env)${NC}"

    echo ""
    echo -e "  ℹ️  v2.0 changes:"
    echo "       New: Unified installer (this script)"
    echo "       New: Update mechanism (./install.sh --update)"
    echo "       New: Better error handling + pagination"

    if command -v git &>/dev/null && git -C "$SCRIPT_DIR" rev-parse &>/dev/null 2>&1; then
        git -C "$SCRIPT_DIR" pull origin main 2>/dev/null || true
        echo -e "${GREEN}  ✅ v2.0 code pulled${NC}"
    fi
}

migrate_from_v1_native() {
    echo ""
    echo -e "${CYAN}  📦 Migrating v1.0 Native installation...${NC}"

    local backup_dir="${NATIVE_INSTALL_DIR}-v1-backup-$(date +%Y%m%d)"
    cp -r "$NATIVE_INSTALL_DIR" "$backup_dir" 2>/dev/null || true
    echo -e "${GREEN}  ✅ Backup created: $backup_dir/${NC}"

    # Preserve .env
    [ -f "$NATIVE_INSTALL_DIR/.env" ] && \
        cp "$NATIVE_INSTALL_DIR/.env" /tmp/interface-pro-env-backup

    echo -e "${GREEN}  ✅ Native migration prepared — re-running installer...${NC}"
}

check_existing_install() {
    local migrated=false

    # Remote check
    if [ -f "$SCRIPT_DIR/.env" ] && [ -f "$SCRIPT_DIR/server.py" ]; then
        local current_ver
        current_ver=$(cat "$SCRIPT_DIR/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "")
        if [ "${current_ver:-0}" = "1.0.0" ] || [ -z "$current_ver" ]; then
            echo -e "${YELLOW}  📁 Existing Remote installation found (v1.0 detected)${NC}"
            if [ "$UNATTENDED" = false ]; then
                read -rp "     Migrate to v2.0? [Y/n]: " migrate_answer
                migrate_answer="${migrate_answer:-Y}"
                if [[ "$migrate_answer" =~ ^[Yy]$ ]]; then
                    migrate_from_v1_remote
                    migrated=true
                fi
            fi
        fi
    fi

    # Native check
    if [ -d "$NATIVE_INSTALL_DIR" ] && [ ! -f "$NATIVE_INSTALL_DIR/install.sh" ]; then
        echo -e "${YELLOW}  📁 Existing Native installation found at $NATIVE_INSTALL_DIR${NC}"
        if [ "$UNATTENDED" = false ]; then
            read -rp "     Migrate to v2.0? [Y/n]: " migrate_answer
            migrate_answer="${migrate_answer:-Y}"
            if [[ "$migrate_answer" =~ ^[Yy]$ ]]; then
                migrate_from_v1_native
                migrated=true
            fi
        fi
    fi

    # Restore native .env after migration
    if [ "$migrated" = true ] && [ -f /tmp/interface-pro-env-backup ]; then
        mkdir -p "$NATIVE_INSTALL_DIR"
        mv /tmp/interface-pro-env-backup "$NATIVE_INSTALL_DIR/.env"
    fi
}

# ─── Uninstall ─────────────────────────────────────────────────────────────────
cmd_uninstall() {
    local os
    os=$(detect_os)
    local keep_config=false
    for arg in "$@"; do
        [ "$arg" = "--keep-config" ] && keep_config=true
    done

    if [ "$os" = "batocera" ] || [ "$MODE" = "native" ]; then
        uninstall_native "$keep_config"
    else
        uninstall_remote "$keep_config"
    fi
}

uninstall_remote() {
    local keep_config=${1:-false}
    echo -e "${RED}  ── Remote Mode Uninstall ────────────────────────────────────────${NC}"
    echo ""

    if [ "$UNATTENDED" = false ]; then
        read -rp "  This will stop the server and remove the venv. Continue? [y/N]: " confirm
        confirm="${confirm:-N}"
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }
    fi

    echo -e "${YELLOW}  [1/3] Stopping server...${NC}"
    pkill -f "server.py" 2>/dev/null || true
    echo -e "${GREEN}  ✅ Server stopped (or was not running)${NC}"

    echo -e "${YELLOW}  [2/3] Removing virtual environment...${NC}"
    rm -rf "$SCRIPT_DIR/.venv"
    echo -e "${GREEN}  ✅ .venv removed${NC}"

    echo -e "${YELLOW}  [3/3] Cleaning up...${NC}"
    if [ "$keep_config" = false ] && [ -f "$SCRIPT_DIR/.env" ]; then
        read -rp "  Also remove .env (SSH credentials)? [y/N]: " del_env
        del_env="${del_env:-N}"
        if [[ "$del_env" =~ ^[Yy]$ ]]; then
            rm -f "$SCRIPT_DIR/.env"
            echo -e "${GREEN}  ✅ .env removed${NC}"
        else
            echo -e "${CYAN}  ℹ  .env preserved${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}  ✅ Remote uninstall complete.${NC}"
    echo "  Project files are still in: $SCRIPT_DIR"
    echo "  To reinstall: ./install.sh"
}

uninstall_native() {
    local keep_config=${1:-false}
    echo -e "${RED}  ── Native Mode Uninstall ─────────────────────────────────────────${NC}"
    echo ""

    if [ ! -d "$NATIVE_INSTALL_DIR" ]; then
        echo -e "${YELLOW}  No native installation found at $NATIVE_INSTALL_DIR${NC}"
        exit 0
    fi

    if [ "$UNATTENDED" = false ]; then
        read -rp "  Remove $NATIVE_INSTALL_DIR and autostart entry? [y/N]: " confirm
        confirm="${confirm:-N}"
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }
    fi

    echo -e "${YELLOW}  [1/4] Stopping server...${NC}"
    pkill -f "server.py" 2>/dev/null || true
    fuser -k 8989/tcp &>/dev/null 2>&1 || true
    echo -e "${GREEN}  ✅ Server stopped${NC}"

    echo -e "${YELLOW}  [2/4] Removing autostart from custom.sh...${NC}"
    if [ -f "$NATIVE_CUSTOM_SH" ]; then
        sed -i '/interface-pro/d' "$NATIVE_CUSTOM_SH"
        sed -i '/WebDashboard PRO/d' "$NATIVE_CUSTOM_SH"
        echo -e "${GREEN}  ✅ Autostart entry removed${NC}"
    fi

    echo -e "${YELLOW}  [3/4] Removing installation directory...${NC}"
    rm -rf "$NATIVE_INSTALL_DIR"
    echo -e "${GREEN}  ✅ $NATIVE_INSTALL_DIR removed${NC}"

    echo -e "${YELLOW}  [4/4] Saving overlay...${NC}"
    batocera-save-overlay &>/dev/null || true
    echo -e "${GREEN}  ✅ Overlay saved${NC}"

    echo ""
    echo -e "${GREEN}  ✅ Native uninstall complete.${NC}"
}

# ─── Status ────────────────────────────────────────────────────────────────────
cmd_status() {
    local os
    os=$(detect_os)

    # Determine mode
    local mode="REMOTE"
    local install_dir="$SCRIPT_DIR"
    if [ "$os" = "batocera" ] || [ -d "$NATIVE_INSTALL_DIR" ]; then
        mode="NATIVE"
        install_dir="$NATIVE_INSTALL_DIR"
    fi

    # Version
    local version
    version=$(cat "$install_dir/version.txt" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

    # Config check
    local config_env="$install_dir/.env"
    local config_status="❌ .env missing"
    [ -f "$config_env" ] && config_status="✅ .env exists"

    # Port
    local port="unknown"
    if [ -f "$config_env" ]; then
        port=$(grep "^PORT=" "$config_env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || echo "$DEFAULT_PORT")
    fi
    [ -z "$port" ] && port="$DEFAULT_PORT"

    # Process check
    local pid
    pid=$(pgrep -f "server.py" 2>/dev/null | head -1 || echo "")
    local proc_status="❌ Not running"
    [ -n "$pid" ] && proc_status="✅ Running (PID $pid)"

    # URL
    local url="http://localhost:${port}"
    [ "$mode" = "NATIVE" ] && url="http://batocera.local:${port}"

    # Update check
    local update_info="⚠️  Could not check"
    local remote_ver
    remote_ver=$(curl -sf --max-time 5 \
        "https://raw.githubusercontent.com/DavidSchuchert/Batocera-WebDashboard-Pro/main/version.txt" \
        2>/dev/null | tr -d '[:space:]' || echo "")
    if [ -n "$remote_ver" ]; then
        if [ "$version" = "$remote_ver" ]; then
            update_info="✅ Up to date"
        else
            update_info="📦 Update available → ${remote_ver}"
        fi
    fi

    echo ""
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo    "  Batocera WebDashboard PRO — Status"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    printf  "  %-12s %s\n" "Mode:"     "$mode"
    printf  "  %-12s %s\n" "Version:"  "$version"
    printf  "  %-12s %s\n" "Port:"     "$port"
    printf  "  %-12s %s\n" "Process:"  "$proc_status"
    printf  "  %-12s %s\n" "URL:"      "$url"
    printf  "  %-12s %s\n" "Config:"   "$config_status"
    printf  "  %-12s %s\n" "Update:"   "$update_info"
    echo -e "${CYAN}  ═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Exit non-zero if not running
    [ -z "$pid" ] && return 1
    return 0
}

# ─── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_banner

    case "$COMMAND" in
        update)    cmd_update "$@"; return ;;
        uninstall) cmd_uninstall "$@"; return ;;
        status)    cmd_status; return ;;
    esac

    # Detect OS
    local os
    os=$(detect_os)
    echo -e "  Detected platform: ${GREEN}${os}${NC}"

    # Windows notes
    if [ "$os" = "windows" ]; then
        show_windows_notes
        if ! command -v bash &>/dev/null; then
            echo -e "${RED}  Error: Install WSL or Git Bash to use this installer.${NC}"
            exit 1
        fi
    fi

    # Check for existing v1 installations and offer migration
    check_existing_install

    # Select mode
    select_mode "$os"
    echo -e "  Installation mode: ${GREEN}${MODE}${NC}"
    echo ""

    # Run mode-specific install
    case "$MODE" in
        native) install_native ;;
        remote) install_remote ;;
        *)
            echo -e "${RED}  Error: Unknown mode '$MODE'. Use 'remote' or 'native'.${NC}"
            exit 1
            ;;
    esac
}

main
