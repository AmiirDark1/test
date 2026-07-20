#!/bin/bash
# ============================================================
# 🚀 Minecraft Admin Panel - Setup & Installation Script
# ============================================================
# This script installs prerequisites and starts the panel
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║       🚀 Minecraft Admin Panel - Setup                    ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}Starting setup at $(date)${NC}\n"

# ============================================================
# 1️⃣  CHECK PREREQUISITES
# ============================================================
echo -e "${BOLD}${YELLOW}"
echo "📋 Step 1/4: Checking prerequisites..."
echo -e "${NC}"

# Function to check if a command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✅ $2 detected: $(command -v $1)${NC}"
        return 0
    else
        echo -e "${RED}❌ $2 not found! Please install $2 first.${NC}"
        return 1
    fi
}

check_command "node" "Node.js"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}   Version: $(node --version)${NC}"
fi

check_command "npm" "npm"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}   Version: $(npm --version)${NC}"
fi

# Check Docker (optional)
DOCKER_MODE=true
if ! check_command "docker" "Docker"; then
    echo -e "${YELLOW}   ⚠ Docker not found - will run panel in standalone mode${NC}"
    echo -e "${YELLOW}   ➡ Download from: https://docker.com/${NC}"
    DOCKER_MODE=false
fi

if ! check_command "docker-compose" "Docker Compose" && ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo -e "${YELLOW}   ⚠ Docker Compose not found - will run panel in standalone mode${NC}"
    DOCKER_MODE=false
fi

# ============================================================
# 2️⃣  INSTALL DEPENDENCIES
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 2/4: Installing dependencies..."
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

if [ -f "package.json" ]; then
    echo -e "${CYAN}📦 Installing npm packages...${NC}"
    npm install
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ npm dependencies installed successfully.${NC}"
    else
        echo -e "${RED}❌ npm install failed!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ No package.json found in current directory.${NC}"
fi

# ============================================================
# 3️⃣  START SERVICES
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 3/4: Starting services..."
echo -e "${NC}"

if [ "$DOCKER_MODE" = false ]; then
    echo -e "${CYAN}🖥 Starting panel in standalone mode...${NC}"
    echo -e "${YELLOW}   Make sure your Minecraft server has RCON enabled!${NC}"
    echo -e "${YELLOW}   Edit start-panel.bat or set env vars to configure RCON.${NC}\n"

    if [ -f "server.js" ]; then
        echo -e "${GREEN}✅ Panel server starting on http://localhost:3000${NC}"
        node server.js &
        PANEL_PID=$!
        echo $PANEL_PID > /tmp/mc-panel.pid
        echo -e "${YELLOW}   Panel PID: $PANEL_PID${NC}"
    else
        echo -e "${RED}❌ server.js not found!${NC}"
        exit 1
    fi
else
    echo -e "${CYAN}🐳 Starting containers with Docker Compose...${NC}"

    # Navigate to docker-compose.yml location
    COMPOSE_DIR="$SCRIPT_DIR"
    if [ -f "../docker-compose.yml" ]; then
        COMPOSE_DIR="$SCRIPT_DIR/.."
    elif [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
        COMPOSE_DIR="$SCRIPT_DIR"
    fi

    cd "$COMPOSE_DIR" || exit 1

    # Try docker compose (v2) first, then docker-compose (v1)
    if docker compose version &> /dev/null 2>&1; then
        docker compose up -d --build
    else
        docker-compose up -d --build
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Docker containers started successfully.${NC}"
    else
        echo -e "${RED}❌ Docker Compose failed!${NC}"
        echo -e "${YELLOW}   Trying to continue with standalone mode...${NC}"

        cd "$SCRIPT_DIR"
        echo -e "${CYAN}🖥 Starting panel in standalone mode (fallback)...${NC}"
        node server.js &
        PANEL_PID=$!
        echo $PANEL_PID > /tmp/mc-panel.pid
    fi
fi

# ============================================================
# 4️⃣  OPEN BROWSER
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 4/4: Opening panel in browser..."
echo -e "${NC}"

echo -e "${CYAN}🔗 Opening http://localhost:3000 in your browser...${NC}"

# Try to open browser (Linux)
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:3000" 2>/dev/null
elif command -v gnome-open &> /dev/null; then
    gnome-open "http://localhost:3000" 2>/dev/null
elif command -v sensible-browser &> /dev/null; then
    sensible-browser "http://localhost:3000" 2>/dev/null
fi

# ============================================================
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║       ✅ Setup Complete!                                  ║"
echo "║                                                          ║"
echo "║   🌐 Panel URL: http://localhost:3000                     ║"
echo "║                                                          ║"
echo "║   📝 RCON Password: minecraft                             ║"
echo "║                                                          ║"
echo "║   📌 To view logs:  docker-compose logs -f                ║"
echo "║   📌 To stop:       docker-compose down                   ║"
echo "║   📌 To restart:    docker-compose restart                ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}✅ Panel is running at: http://localhost:3000${NC}"