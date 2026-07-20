#!/bin/bash
# ============================================================
# 🚀 Minecraft Server + Admin Panel - One-Line Installer
# ============================================================
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/AmiirDark1/test/master/install.sh)
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="https://github.com/AmiirDark1/test.git"
PROJECT_DIR="mc-server-panel"

echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║     🚀  Minecraft Server + Admin Panel                        ║"
echo "║         One-Click Installer                                  ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 1️⃣  DETECT OS & INSTALL DOCKER
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 1/4: Checking & Installing Docker...${NC}"

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif command -v sw_vers &> /dev/null; then
        OS="macos"
    else
        OS="unknown"
    fi
    echo -e "${CYAN}  Detected OS: $OS${NC}"
}

install_docker() {
    echo -e "${YELLOW}  ⏳ Docker not found. Installing Docker automatically...${NC}"
    
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
    elif [ "$OS" = "macos" ]; then
        echo -e "${RED}  ❌ MacOS: Please install Docker Desktop manually from:${NC}"
        echo -e "${YELLOW}     https://www.docker.com/products/docker-desktop/${NC}"
        exit 1
    else
        echo -e "${RED}  ❌ Unsupported OS. Please install Docker manually.${NC}"
        exit 1
    fi
    
    # Add current user to docker group
    sudo usermod -aG docker $USER 2>/dev/null || true
    
    echo -e "${GREEN}  ✅ Docker installed successfully!${NC}"
}

install_docker_compose() {
    echo -e "${YELLOW}  ⏳ Docker Compose not found. Installing...${NC}"
    
    # Try docker compose v2 first (built-in)
    if docker compose version &> /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Docker Compose v2 is already available (built into Docker)${NC}"
        return 0
    fi
    
    # Install docker-compose plugin or standalone
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
    sudo chmod +x /usr/local/bin/docker-compose 2>/dev/null
    
    if command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}  ✅ Docker Compose installed: $(docker-compose --version)${NC}"
    else
        echo -e "${YELLOW}  ⚠ docker-compose command not in PATH. Trying docker compose v2...${NC}"
        if docker compose version &> /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Docker Compose v2 available${NC}"
        fi
    fi
}

# Check Docker
if command -v docker &> /dev/null; then
    echo -e "${GREEN}  ✅ Docker already installed: $(docker --version)${NC}"
else
    detect_os
    install_docker
fi

# Check Docker daemon
if ! docker info &> /dev/null 2>&1; then
    echo -e "${YELLOW}  ⏳ Starting Docker daemon...${NC}"
    sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sleep 2
    if ! docker info &> /dev/null 2>&1; then
        echo -e "${RED}  ❌ Docker daemon is not running!${NC}"
        echo -e "${YELLOW}     Please start Docker Desktop and try again.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  ✅ Docker daemon is running${NC}"

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}  ✅ Docker Compose already installed: $(docker-compose --version)${NC}"
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    echo -e "${GREEN}  ✅ Docker Compose v2 available${NC}"
    COMPOSE_CMD="docker compose"
else
    install_docker_compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="docker compose"
    fi
fi

# ============================================================
# 2️⃣  GET PROJECT FILES
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 2/4: Getting project files...${NC}"

# Check if we're already in the project directory
if [ -f "docker-compose.yml" ] && [ -d "mc-panel" ]; then
    echo -e "${GREEN}  ✅ Project files found in current directory.${NC}"
    PROJECT_DIR="."
elif [ -d "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo -e "${GREEN}  ✅ Project already cloned in ./$PROJECT_DIR${NC}"
    cd "$PROJECT_DIR"
    PROJECT_DIR="."
else
    echo -e "${CYAN}  📥 Cloning project from GitHub...${NC}"
    if command -v git &> /dev/null; then
        git clone --depth 1 "$REPO_URL" "$PROJECT_DIR" 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ Git clone failed, trying download as zip...${NC}"
            curl -Ls "https://github.com/AmiirDark1/test/archive/master.tar.gz" -o /tmp/mc-panel.tar.gz
            mkdir -p "$PROJECT_DIR"
            tar -xzf /tmp/mc-panel.tar.gz -C "$PROJECT_DIR" --strip-components=1 2>/dev/null || {
                echo -e "${RED}  ❌ Failed to get project files!${NC}"
                exit 1
            }
        }
    else
        echo -e "${YELLOW}  ⚠ Git not found, downloading as zip...${NC}"
        curl -Ls "https://github.com/AmiirDark1/test/archive/master.tar.gz" -o /tmp/mc-panel.tar.gz
        mkdir -p "$PROJECT_DIR"
        tar -xzf /tmp/mc-panel.tar.gz -C "$PROJECT_DIR" --strip-components=1 2>/dev/null || {
            echo -e "${RED}  ❌ Failed to get project files!${NC}"
            exit 1
        }
    fi
    cd "$PROJECT_DIR"
    PROJECT_DIR="."
    echo -e "${GREEN}  ✅ Project files downloaded.${NC}"
fi

# ============================================================
# 3️⃣  SETUP DATA & BUILD
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 3/4: Setting up data & building images...${NC}"

# Create data directory
if [ ! -d "data" ]; then
    mkdir -p data
    echo -e "${GREEN}  ✅ Created data directory${NC}"
else
    echo -e "${YELLOW}  📁 Data directory exists${NC}"
fi

# Create subdirectories
for dir in world world_nether world_the_end plugins logs cache; do
    mkdir -p "data/$dir"
done
echo -e "${GREEN}  ✅ Data subdirectories created${NC}"

# Build panel image
echo -e "${CYAN}  🏗️ Building admin panel image...${NC}"
docker build -t mc-admin-panel:latest ./mc-panel
echo -e "${GREEN}  ✅ Panel image built${NC}"

# ============================================================
# 4️⃣  START CONTAINERS
# ============================================================
echo -e "\n${BOLD}${YELLOW}📋 Step 4/4: Starting services...${NC}"

echo -e "${CYAN}  🐳 Starting containers with Docker Compose...${NC}"
$COMPOSE_CMD up -d --build

echo -e "${GREEN}  ✅ Containers started${NC}"

# Show status
echo -e "\n${CYAN}  📊 Container Status:${NC}"
$COMPOSE_CMD ps

# ============================================================
# DONE
# ============================================================
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║       ✅  INSTALLATION COMPLETE!                              ║"
echo "║                                                              ║"
echo "║   🌐  Admin Panel:  http://localhost:3000                     ║"
echo "║   🎮  Minecraft:    localhost:25565                           ║"
echo "║   🔧  RCON:         localhost:25575 / password: minecraft     ║"
echo "║                                                              ║"
echo "║   📁  Server Data:  $(pwd)/data/                              ║"
echo "║                                                              ║"
echo "║   📌  Useful Commands:                                        ║"
echo "║       $COMPOSE_CMD logs -f    → View all logs               ║"
echo "║       $COMPOSE_CMD down       → Stop all services            ║"
echo "║       $COMPOSE_CMD restart    → Restart services             ║"
echo "║       docker exec -it minecraft rcon-cli   → RCON console    ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Open browser
echo -e "${CYAN}  🔗 Opening panel in browser...${NC}"
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:3000" 2>/dev/null
elif command -v gnome-open &> /dev/null; then
    gnome-open "http://localhost:3000" 2>/dev/null
elif command -v open &> /dev/null; then
    open "http://localhost:3000" 2>/dev/null
fi

echo -e "${GREEN}\n  ✅ Panel ready at: http://localhost:3000${NC}"
echo -e "${YELLOW}  💡 Add this to your terminal for future use:${NC}"
echo -e "${CYAN}     bash <(curl -Ls https://raw.githubusercontent.com/AmiirDark1/test/master/install.sh)${NC}\n"