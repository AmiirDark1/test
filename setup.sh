#!/bin/bash
# ============================================================
# 🚀 Minecraft Server + Admin Panel - Full Project Setup
# ============================================================
# This script sets up the ENTIRE project:
#   - Minecraft Paper Server (Docker)
#   - Admin Panel (Docker)
#   - Persistent data storage
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║     🚀  Minecraft Server + Admin Panel                        ║"
echo "║         Full Project Setup Script                             ║"
echo "║                                                              ║"
echo "║     📦 Docker Edition                                         ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}  Starting setup at $(date)${NC}\n"
echo -e "${YELLOW}  Project Root: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)${NC}\n"

# ============================================================
# 1️⃣  CHECK PREREQUISITES
# ============================================================
echo -e "${BOLD}${YELLOW}"
echo "📋 Step 1/5: Checking prerequisites..."
echo -e "${NC}"

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}  ✅ $2: $(command -v $1)${NC}"
        return 0
    else
        echo -e "${RED}  ❌ $2 not found!${NC}"
        if [ -n "$3" ]; then
            echo -e "${YELLOW}     ➡ Download: $3${NC}"
        fi
        return 1
    fi
}

check_command "docker" "Docker" "https://docker.com/"
DOCKER_OK=$?

check_command "docker-compose" "Docker Compose" "https://docs.docker.com/compose/"
COMPOSE_OK=$?

# Check for docker compose v2
if [ "$COMPOSE_OK" -ne 0 ]; then
    if docker compose version &> /dev/null; then
        echo -e "${GREEN}  ✅ Docker Compose (v2 built-in): $(docker compose version --short 2>/dev/null)${NC}"
        COMPOSE_OK=0
        USE_COMPOSE_V2=true
    fi
fi

if [ "$DOCKER_OK" -ne 0 ]; then
    echo -e "\n${RED}  ❌ Docker is required for this setup!${NC}"
    echo -e "${YELLOW}     Please install Docker Desktop from: https://docker.com/${NC}"
    exit 1
fi

if [ "$COMPOSE_OK" -ne 0 ]; then
    echo -e "\n${RED}  ❌ Docker Compose is required!${NC}"
    echo -e "${YELLOW}     Install from: https://docs.docker.com/compose/install/${NC}"
    exit 1
fi

# Check Docker daemon
echo -e "${CYAN}  🔍 Checking Docker daemon...${NC}"
if docker info &> /dev/null; then
    echo -e "${GREEN}  ✅ Docker daemon is running${NC}"
else
    echo -e "${RED}  ❌ Docker daemon is NOT running!${NC}"
    echo -e "${YELLOW}     Please start Docker Desktop and try again.${NC}"
    exit 1
fi

# ============================================================
# 2️⃣  SETUP DATA DIRECTORY
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 2/5: Setting up persistent data directory..."
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    echo -e "${GREEN}  ✅ Created data directory: $DATA_DIR${NC}"
else
    echo -e "${YELLOW}  📁 Data directory already exists: $DATA_DIR${NC}"
fi

# Create subdirectories
for dir in world world_nether world_the_end plugins logs cache; do
    if [ ! -d "$DATA_DIR/$dir" ]; then
        mkdir -p "$DATA_DIR/$dir"
    fi
done

echo -e "${GREEN}  ✅ Data subdirectories created.${NC}"

# ============================================================
# 3️⃣  BUILD DOCKER IMAGES
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 3/5: Building Docker images..."
echo -e "${NC}"

cd "$SCRIPT_DIR"

echo -e "${CYAN}  🏗️ Building mc-admin-panel image...${NC}"
docker build -t mc-admin-panel:latest ./mc-panel
if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✅ Panel image built successfully.${NC}"
else
    echo -e "${RED}  ❌ Panel image build failed!${NC}"
    exit 1
fi

echo -e "${CYAN}  🔍 Checking Minecraft server image...${NC}"
MC_IMAGE=$(docker images -q itzg/minecraft-server 2>/dev/null)
if [ -z "$MC_IMAGE" ]; then
    echo -e "${YELLOW}  ⏳ Minecraft server image not found locally.${NC}"
    echo -e "${YELLOW}     It will be pulled automatically when starting.${NC}"
else
    echo -e "${GREEN}  ✅ Minecraft server image found locally.${NC}"
fi

# ============================================================
# 4️⃣  START CONTAINERS
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 4/5: Starting containers..."
echo -e "${NC}"

cd "$SCRIPT_DIR"

echo -e "${CYAN}  🐳 Starting services with Docker Compose...${NC}"
echo -e "${YELLOW}     🟢 Minecraft Server  → port 25565 (game)${NC}"
echo -e "${YELLOW}     🔵 RCON              → port 25575${NC}"
echo -e "${YELLOW}     🟣 Admin Panel       → port 3000 (web)${NC}\n"

if [ "$USE_COMPOSE_V2" = true ]; then
    docker compose up -d --build
else
    docker-compose up -d --build
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✅ All containers started successfully.${NC}\n"
else
    echo -e "${RED}  ❌ Failed to start containers!${NC}"
    exit 1
fi

# ============================================================
# 5️⃣  WAIT FOR SERVICES & SHOW INFO
# ============================================================
echo -e "\n${BOLD}${YELLOW}"
echo "📋 Step 5/5: Waiting for services to be ready..."
echo -e "${NC}"

echo -e "${CYAN}  ⏳ Waiting for Minecraft server to start (this may take a minute)...${NC}"
MAX_WAIT=120
WAITED=0
SERVER_READY=false

while [ $WAITED -lt $MAX_WAIT ]; do
    LOGS=$(docker logs minecraft 2>&1)
    if echo "$LOGS" | grep -q "Done ("; then
        SERVER_READY=true
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    if [ $((WAITED % 10)) -eq 0 ]; then
        echo -e "${YELLOW}     Still waiting... ($WAITED seconds)${NC}"
    fi
done

if [ "$SERVER_READY" = true ]; then
    echo -e "${GREEN}  ✅ Minecraft server is ready!${NC}"
else
    echo -e "${YELLOW}  ⚠ Timed out waiting for server. Check logs with: docker logs minecraft${NC}"
fi

# Show container status
echo -e "\n${CYAN}  📊 Container Status:${NC}"
if [ "$USE_COMPOSE_V2" = true ]; then
    docker compose ps
else
    docker-compose ps
fi

# ============================================================
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║       ✅  SETUP COMPLETE!                                     ║"
echo "║                                                              ║"
echo "║   🌐  Admin Panel:  http://localhost:3000                     ║"
echo "║   🎮  Minecraft:    localhost:25565                           ║"
echo "║   🔧  RCON:         localhost:25575 / password: minecraft     ║"
echo "║                                                              ║"
echo "║   📁  Server Data:  ./data/                                   ║"
echo "║                                                              ║"
echo "║   📌  Useful Commands:                                        ║"
echo "║       docker-compose logs -f    → View all logs               ║"
echo "║       docker-compose down       → Stop all services           ║"
echo "║       docker-compose restart    → Restart services            ║"
echo "║       docker-compose ps         → Container status            ║"
echo "║       docker exec -it minecraft rcon-cli   → RCON console     ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Open browser
echo -e "${CYAN}  🔗 Opening Admin Panel in your browser...${NC}"
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:3000" 2>/dev/null
elif command -v gnome-open &> /dev/null; then
    gnome-open "http://localhost:3000" 2>/dev/null
elif command -v open &> /dev/null; then
    open "http://localhost:3000" 2>/dev/null
fi

echo -e "${GREEN}\n  ✅ All done! Panel is available at: http://localhost:3000${NC}\n"