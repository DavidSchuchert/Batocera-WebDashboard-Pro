#!/bin/bash

# --- Configuration ---
PORT_DEFAULT=8989
VENV_DIR=".venv"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "  ____        _                             ____  "
echo " | __ )  __ _| |_ ___   ___ ___ _ __ __ _  |  _ \ _ __ ___  "
echo " |  _ \ / _\` | __/ _ \ / __/ _ \ '__/ _\` | | |_) | '__/ _ \ "
echo " | |_) | (_| | || (_) | (_|  __/ | | (_| | |  __/| | | (_) |"
echo " |____/ \__,_|\__\___/ \___\___|_|  \__,_| |_|   |_|  \___/ "
echo "                                                             "
echo -e "${GREEN}      >>> Batocera Interface PRO (v1.0) <<<${NC}"
echo ""

# --- Dependency Check ---
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed.${NC}"
    exit 1
fi

# --- Setup Virtual Environment ---
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}[1/3] Creating virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
fi

echo -e "${YELLOW}[2/3] Updating dependencies...${NC}"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip &> /dev/null
pip install -r requirements.txt &> /dev/null

# --- Configuration Check (.env) ---
if [ ! -f .env ]; then
    echo -e "${YELLOW}[3/3] First Run Setup:${NC}"
    read -p "  Enter Batocera IP: " IP
    read -p "  Enter Batocera Username [root]: " USER
    USER=${USER:-root}
    read -p "  Enter Batocera Password [linux]: " PASS
    PASS=${PASS:-linux}
    read -p "  Enter Web UI Port [$PORT_DEFAULT]: " PORT
    PORT=${PORT:-$PORT_DEFAULT}

    cat > .env << EOF
BATOCERA_HOST=$IP
BATOCERA_USER=$USER
BATOCERA_PASS=$PASS
PORT=$PORT
EOF
    echo -e "${GREEN}Configuration saved to .env${NC}"
else
    echo -e "${YELLOW}[3/3] Configuration loaded from .env${NC}"
fi

# --- Start Server ---
echo -e "${GREEN}"
echo "----------------------------------------------------"
echo "  Batocera Interface PRO is starting..."
echo "  URL: http://localhost:$(grep PORT .env | cut -d'=' -f2)"
echo "----------------------------------------------------"
echo -e "${NC}"

"$VENV_DIR/bin/python3" server.py
