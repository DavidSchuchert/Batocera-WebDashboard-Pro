#!/bin/bash

# --- Configuration ---
INSTALL_DIR="/userdata/system/interface-pro"
CUSTOM_SH="/userdata/system/custom.sh"
START_SCRIPT="$INSTALL_DIR/start_native.sh"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}----------------------------------------------------"
echo "  Batocera Web Dashboard PRO - Native Installer"
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
if [ "$CURRENT_DIR" != "$INSTALL_DIR" ]; then
    cp -r "$CURRENT_DIR"/* "$INSTALL_DIR/"
    echo -e "${CYAN}  -> Files deployed to $INSTALL_DIR${NC}"
fi

# 3. Install Dependencies (Flask)
echo -e "${YELLOW}[2/3] Checking dependencies...${NC}"
PYTHON_EXEC="python3"

pip3 install flask --user &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}  -> Creating virtual environment...${NC}"
    python3 -m venv "$INSTALL_DIR/.venv"
    "$INSTALL_DIR/.venv/bin/pip" install flask &> /dev/null
    PYTHON_EXEC="$INSTALL_DIR/.venv/bin/python3"
fi

# 4. Create dedicated start script (better for debugging)
echo -e "${YELLOW}[3/3] Creating start script and configuring custom.sh...${NC}"

cat <<EOF > "$START_SCRIPT"
#!/bin/bash
# Batocera Interface PRO - Boot Script
exec > "$INSTALL_DIR/boot.log" 2>&1
echo "Starting Interface PRO at \$(date)"
sleep 15
cd "$INSTALL_DIR"
$PYTHON_EXEC server.py
EOF
chmod +x "$START_SCRIPT"

# Configure custom.sh
if [ ! -f "$CUSTOM_SH" ]; then
    echo "#!/bin/bash" > "$CUSTOM_SH"
fi

# Remove old entries
sed -i '/interface-pro/d' "$CUSTOM_SH"

# Add clean entry
echo "" >> "$CUSTOM_SH"
echo "# Start Batocera Interface PRO" >> "$CUSTOM_SH"
echo "$START_SCRIPT &" >> "$CUSTOM_SH"
chmod +x "$CUSTOM_SH"

# Save Overlay
echo -e "${YELLOW}  -> Saving system overlay...${NC}"
batocera-save-overlay &> /dev/null

echo -e " 🚀  Added launch command to /userdata/system/custom.sh"
echo -e " 💾  Ran 'batocera-save-overlay' for persistence"
echo -e " 🔄  PLEASE REBOOT to test the automatic startup!"
echo -e "----------------------------------------------------"
echo "  Installation Complete!"
echo "  If it doesn't start, check: $INSTALL_DIR/boot.log"
echo -e "----------------------------------------------------${NC}"
