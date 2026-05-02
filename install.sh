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
    echo    "  ╚══════════════════════════════════════════════════════════════╝${NC}"
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

# ─── Native Installation ───────────────────────────────────────────────────────
install_native() {
    echo -e "${CYAN}  ── Native Mode Setup ──────────────────────────────────────────${NC}"
    echo ""

    # Must be on Batocera
    if [ ! -d "/userdata/system" ]; then
        echo -e "${RED}  Error: Native mode requires a Batocera system.${NC}"
        echo "  /userdata/system not found. Are you running on Batocera?"
        exit 1
    fi

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

    # custom.sh
    if [ ! -f "$NATIVE_CUSTOM_SH" ]; then
        echo "#!/bin/bash" > "$NATIVE_CUSTOM_SH"
    fi
    sed -i '/interface-pro/d' "$NATIVE_CUSTOM_SH"
    {
        echo ""
        echo "# Start Batocera WebDashboard PRO"
        echo "$start_script &"
    } >> "$NATIVE_CUSTOM_SH"
    chmod +x "$NATIVE_CUSTOM_SH"

    batocera-save-overlay &>/dev/null || true

    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════════╗"
    echo    "  ║  ✅ Native installation complete!                              ║"
    echo    "  ║                                                                ║"
    echo    "  ║  The dashboard starts automatically on next boot.              ║"
    printf  "  ║  URL: http://batocera.local:%s                                  ║\n" "$PORT"
    echo    "  ║  Logs: $NATIVE_INSTALL_DIR/boot.log               ║"
    echo    "  ║                                                                ║"
    echo -e "  ║  Reboot to activate autostart, or run manually:               ║"
    echo    "  ║    $start_script                        ║"
    echo -e "  ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    batocera-save-overlay &>/dev/null || true
}

# ─── Update (stub — fully implemented in Phase 2) ──────────────────────────────
cmd_update() {
    echo -e "${YELLOW}  Update mechanism — implemented in v2.1${NC}"
    echo "  For now: git pull origin main && pip install -r requirements.txt"
    exit 0
}

# ─── Uninstall (stub — fully implemented in Phase 3) ──────────────────────────
cmd_uninstall() {
    echo -e "${YELLOW}  Unified uninstall — implemented in Phase 3${NC}"
    echo "  For native: use batocera-native/uninstall.sh"
    exit 0
}

# ─── Status (stub — fully implemented in Phase 3) ─────────────────────────────
cmd_status() {
    echo -e "${YELLOW}  Status command — implemented in Phase 3${NC}"
    exit 0
}

# ─── Main ──────────────────────────────────────────────────────────────────────
main() {
    print_banner

    case "$COMMAND" in
        update)    cmd_update; return ;;
        uninstall) cmd_uninstall; return ;;
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
