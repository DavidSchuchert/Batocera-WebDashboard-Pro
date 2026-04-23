#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/userdata/system/interface-pro"
CUSTOM_SH="/userdata/system/custom.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}----------------------------------------------------"
echo "  Batocera Web Dashboard PRO - Uninstaller"
echo -e "----------------------------------------------------${NC}"

# 1. Stop the running server
echo -e "${YELLOW}[1/4] Stopping running server...${NC}"
fuser -k 8989/tcp &> /dev/null
pkill -f server.py &> /dev/null

# 2. Remove from custom.sh
echo -e "${YELLOW}[2/4] Removing autostart entry from custom.sh...${NC}"
if [ -f "$CUSTOM_SH" ]; then
    sed -i '/interface-pro/d' "$CUSTOM_SH"
fi

# 3. Delete installation directory
echo -e "${YELLOW}[3/4] Deleting installation files...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi

# 4. Save Overlay
echo -e "${YELLOW}[4/4] Saving system overlay...${NC}"
batocera-save-overlay &> /dev/null

echo -e "${GREEN}----------------------------------------------------"
echo "  Uninstallation Complete!"
echo "  All files and autostart entries have been removed."
echo -e "----------------------------------------------------${NC}"
