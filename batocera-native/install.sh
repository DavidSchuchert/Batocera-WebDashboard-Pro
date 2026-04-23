#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/userdata/system/interface-pro"
CUSTOM_SH="/userdata/system/custom.sh"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}----------------------------------------------------"
echo "  Batocera Interface PRO - Native Installer"
echo -e "----------------------------------------------------${NC}"

# 1. Check if running on Batocera
if [ ! -d "/userdata/system" ]; then
    echo -e "${RED}Error: This script must be run on a Batocera system.${NC}"
    exit 1
fi

# 2. Setup Directory & Copy Files
echo -e "${YELLOW}[1/3] Preparing installation directory and copying files...${NC}"
mkdir -p "$INSTALL_DIR"

CURRENT_DIR=$(pwd)
FILES_COPIED=false
if [ "$CURRENT_DIR" != "$INSTALL_DIR" ]; then
    cp -r "$CURRENT_DIR"/* "$INSTALL_DIR/"
    echo -e "${CYAN}  -> Files successfully deployed to $INSTALL_DIR${NC}"
    FILES_COPIED=true
else
    echo -e "${CYAN}  -> Running directly from installation directory.${NC}"
fi

# 3. Install Dependencies (Flask)
echo -e "${YELLOW}[2/3] Checking dependencies...${NC}"
PYTHON_EXEC="python3"
VENV_USED=false

# Try --user install first
pip3 install flask --user &> /dev/null

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}  -> Standard pip restricted. Creating virtual environment...${NC}"
    python3 -m venv "$INSTALL_DIR/.venv"
    "$INSTALL_DIR/.venv/bin/pip" install flask &> /dev/null
    PYTHON_EXEC="$INSTALL_DIR/.venv/bin/python3"
    VENV_USED=true
else
    echo -e "${GREEN}  -> Flask installed globally/user-level.${NC}"
fi

# 4. Setup Autostart (custom.sh)
echo -e "${YELLOW}[3/3] Configuring autostart (custom.sh)...${NC}"

# Remove any old entries to avoid duplicates or wrong paths
if [ -f "$CUSTOM_SH" ]; then
    sed -i '/interface-pro\/server.py/d' "$CUSTOM_SH"
fi

echo "" >> "$CUSTOM_SH"
echo "# Start Batocera Interface PRO on boot" >> "$CUSTOM_SH"
echo "$PYTHON_EXEC $INSTALL_DIR/server.py &" >> "$CUSTOM_SH"
chmod +x "$CUSTOM_SH"

echo -e "${GREEN}  -> Autostart linked successfully.${NC}"

# --- Final Summary ---
echo -e "\n${CYAN}===================================================="
echo -e "🎉  INSTALLATION COMPLETE - ALLES TUTTI! 🎉"
echo -e "====================================================${NC}"
echo -e "What we did for you:"
if [ "$FILES_COPIED" = true ]; then
    echo -e " 📂  Deployed files to ${WHITE}$INSTALL_DIR${NC} (Safe zone)"
fi
if [ "$VENV_USED" = true ]; then
    echo -e " 🐍  Created a dedicated Virtual Environment (Safe & Clean)"
else
    echo -e " 🐍  Used system Python for maximum efficiency"
fi
echo -e " 🚀  Added the launch command to your Batocera boot sequence"
echo -e "----------------------------------------------------"
echo -e "${YELLOW}Access your interface at:${NC}"
echo -e "  🌐  http://batocera.local:8989"
echo -e "  🌐  http://$(ifconfig | grep -A 1 'eth0\|wlan0' | grep 'inet ' | awk '{print $2}' | head -1):8989"
echo -e "----------------------------------------------------"
echo -e "You can start the server manually right now with:"
echo -e "${GREEN}  $PYTHON_EXEC $INSTALL_DIR/server.py &${NC}"
echo -e "${CYAN}====================================================${NC}\n"
