#!/bin/bash
# ============================================================
# 🚀 Minecraft Server Panel - Setup Script (فایل اسیتال)
# ============================================================
# This script installs prerequisites and sets up the
# Minecraft Admin Panel with an HTTP server.
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║     🚀  Minecraft Server Panel                               ║"
echo "║         Setup Script (فایل اسیتال)                           ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 1️⃣  DETECT SYSTEM
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 1/4: Checking System...${NC}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    echo -e "${GREEN}  ✅ OS: $OS $OS_VERSION${NC}"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    echo -e "${GREEN}  ✅ OS: macOS${NC}"
else
    OS="unknown"
    echo -e "${YELLOW}  ⚠ OS: Unknown (assuming Linux-compatible)${NC}"
fi

# Check Architecture
ARCH=$(uname -m)
echo -e "${GREEN}  ✅ Architecture: $ARCH${NC}"

# Check available disk space
AVAILABLE_DISK=$(df -h . | awk 'NR==2 {print $4}')
echo -e "${GREEN}  ✅ Available disk space: $AVAILABLE_DISK${NC}"

# ============================================================
# 2️⃣  INSTALL PREREQUISITES (نصب پیش‌نیازها)
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 2/4: Installing Prerequisites (نصب پیش‌نیازها)...${NC}"

# --- Check / Install Git ---
if command -v git &> /dev/null; then
    echo -e "${GREEN}  ✅ Git: $(git --version)${NC}"
    GIT_AVAILABLE=true
else
    echo -e "${YELLOW}  ⏳ Git not found. Installing...${NC}"
    GIT_AVAILABLE=false
    if command -v apt &> /dev/null; then
        sudo apt update -qq && sudo apt install -y -qq git
    elif command -v yum &> /dev/null; then
        sudo yum install -y git
    elif command -v apk &> /dev/null; then
        sudo apk add git
    else
        echo -e "${RED}  ❌ Could not install Git automatically. Please install manually.${NC}"
    fi
    if command -v git &> /dev/null; then
        echo -e "${GREEN}  ✅ Git installed: $(git --version)${NC}"
    fi
fi

# --- Check / Install curl ---
if command -v curl &> /dev/null; then
    echo -e "${GREEN}  ✅ curl: available${NC}"
else
    echo -e "${YELLOW}  ⏳ curl not found. Installing...${NC}"
    if command -v apt &> /dev/null; then
        sudo apt install -y -qq curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl
    elif command -v apk &> /dev/null; then
        sudo apk add curl
    fi
fi

# --- Check / Install Docker ---
if command -v docker &> /dev/null; then
    echo -e "${GREEN}  ✅ Docker: $(docker --version)${NC}"
else
    echo -e "${YELLOW}  ⏳ Docker not found. Installing Docker automatically...${NC}"
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    sudo usermod -aG docker $USER 2>/dev/null || true
    echo -e "${GREEN}  ✅ Docker installed successfully!${NC}"
    echo -e "${YELLOW}  ⚠ You may need to log out and back in for Docker group changes to take effect.${NC}"
fi

# Check Docker daemon
if ! docker info &> /dev/null 2>&1; then
    echo -e "${YELLOW}  ⏳ Starting Docker daemon...${NC}"
    sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sleep 3
    if ! docker info &> /dev/null 2>&1; then
        echo -e "${RED}  ❌ Docker daemon is not running!${NC}"
        echo -e "${YELLOW}     Please start Docker and try again.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  ✅ Docker daemon is running${NC}"

# --- Check / Install Docker Compose ---
COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}  ✅ Docker Compose: $(docker-compose --version)${NC}"
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ Docker Compose v2 available${NC}"
    COMPOSE_CMD="docker compose"
else
    echo -e "${YELLOW}  ⏳ Docker Compose not found. Installing...${NC}"
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null | grep tag_name | cut -d'"' -f4 2>/dev/null || echo "v2.24.0")
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
    sudo chmod +x /usr/local/bin/docker-compose 2>/dev/null
    if command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}  ✅ Docker Compose installed: $(docker-compose --version)${NC}"
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="docker compose"
    fi
fi

echo -e "\n${GREEN}  ✅ All prerequisites installed!${NC}"

# ============================================================
# 3️⃣  SETUP PROJECT (راه‌اندازی پروژه)
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 3/4: Setting up Project (راه‌اندازی پروژه)...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if project files exist
if [ -f "docker-compose.yml" ] && [ -d "mc-panel" ]; then
    echo -e "${GREEN}  ✅ Project files found in current directory${NC}"
    PROJECT_DIR="."
else
    # Try to get from GitHub
    REPO_URL="https://github.com/AmiirDark1/test.git"
    PROJECT_DIR="mc-server-panel"
    
    echo -e "${CYAN}  📥 Downloading project from GitHub...${NC}"
    if [ "$GIT_AVAILABLE" = true ]; then
        git clone --depth 1 "$REPO_URL" "$PROJECT_DIR" 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Git clone failed, trying zip download...${NC}"
            curl -Ls "https://github.com/AmiirDark1/test/archive/master.tar.gz" -o /tmp/mc-panel.tar.gz
            mkdir -p "$PROJECT_DIR"
            tar -xzf /tmp/mc-panel.tar.gz -C "$PROJECT_DIR" --strip-components=1 2>/dev/null || {
                echo -e "${RED}  ❌ Failed to download project files!${NC}"
                exit 1
            }
        }
    else
        curl -Ls "https://github.com/AmiirDark1/test/archive/master.tar.gz" -o /tmp/mc-panel.tar.gz
        mkdir -p "$PROJECT_DIR"
        tar -xzf /tmp/mc-panel.tar.gz -C "$PROJECT_DIR" --strip-components=1 2>/dev/null || {
            echo -e "${RED}  ❌ Failed to download project files!${NC}"
            exit 1
        }
    fi
    cd "$PROJECT_DIR"
    PROJECT_DIR="."
    echo -e "${GREEN}  ✅ Project downloaded${NC}"
fi

# Create data directory structure
echo -e "${CYAN}  📁 Creating data directories...${NC}"
mkdir -p data
for dir in world world_nether world_the_end plugins logs cache; do
    mkdir -p "data/$dir"
done
echo -e "${GREEN}  ✅ Data directories created${NC}"

# Make scripts executable
chmod +x mc.sh mc-tui.sh 2>/dev/null || true

# Build the admin panel Docker image
echo -e "${CYAN}  🏗️ Building admin panel image...${NC}"
docker build -t mc-admin-panel:latest ./mc-panel
echo -e "${GREEN}  ✅ Panel image built${NC}"

# ============================================================
# 4️⃣  START SERVICES & SHOW PANEL (اجرا و نمایش پنل)
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 4/4: Starting Services & Showing Panel (اجرا و نمایش پنل)...${NC}"

# Stop any existing containers
echo -e "${CYAN}  🛑 Stopping any existing services...${NC}"
$COMPOSE_CMD down 2>/dev/null || true

# Start containers
echo -e "${CYAN}  🐳 Starting containers...${NC}"
$COMPOSE_CMD up -d --build

# Show status
echo -e "\n${CYAN}  📊 Container Status:${NC}"
$COMPOSE_CMD ps

# Wait for panel to be ready
echo -e "\n${YELLOW}  ⏳ Waiting for panel to be ready...${NC}"
for i in $(seq 1 30); do
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Panel is ready!${NC}"
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

# ============================================================
# DONE - Show Panel via HTTP (نمایش پنل با ایچی سرور)
# ============================================================
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║       ✅  SETUP COMPLETE! (راه‌اندازی کامل شد)                ║"
echo "║                                                              ║"
echo "║   🌐  Admin Panel:  http://localhost:3000                     ║"
echo "║   🎮  Minecraft:    localhost:25565                           ║"
echo "║   🔧  RCON:         localhost:25575 / password: minecraft     ║"
echo "║                                                              ║"
echo "║   📁  Server Data:  $(pwd)/data/                              ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Open panel in browser (ایچی سرور / HTTP Server)
echo -e "${CYAN}  🔗 Opening panel in browser...${NC}"
PANEL_URL="http://localhost:3000"
echo -e "${BOLD}${GREEN}  🌐 Panel URL: $PANEL_URL${NC}"

# Try different methods to open browser
if command -v xdg-open &> /dev/null; then
    xdg-open "$PANEL_URL" 2>/dev/null || true
elif command -v gnome-open &> /dev/null; then
    gnome-open "$PANEL_URL" 2>/dev/null || true
elif command -v open &> /dev/null; then
    open "$PANEL_URL" 2>/dev/null || true
elif [ -n "$DISPLAY" ] && command -v sensible-browser &> /dev/null; then
    sensible-browser "$PANEL_URL" 2>/dev/null || true
else
    echo -e "${YELLOW}  ⚠ Could not open browser automatically.${NC}"
    echo -e "${YELLOW}     Open this link manually:${NC}"
    echo -e "${CYAN}     $PANEL_URL${NC}"
fi

# Show useful commands
echo -e "\n${BOLD}${MAGENTA}📌 Useful Commands:${NC}"
echo -e "  ${CYAN}$COMPOSE_CMD logs -f${NC}      → View all logs"
echo -e "  ${CYAN}$COMPOSE_CMD down${NC}         → Stop all services"
echo -e "  ${CYAN}$COMPOSE_CMD restart${NC}      → Restart services"
echo -e "  ${CYAN}docker exec -it minecraft rcon-cli${NC}   → RCON console"
echo -e "  ${CYAN}bash mc-tui.sh${NC}            → Terminal UI manager"
echo -e "  ${CYAN}mc${NC}                        → Quick command (after install)"

echo -e "\n${GREEN}  ✅ Panel is now running at: http://localhost:3000${NC}"
echo -e "${GREEN}     You can access it from any browser on this machine!${NC}"
echo -e ""