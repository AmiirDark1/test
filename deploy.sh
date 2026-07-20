#!/bin/bash
# ============================================================
# 🚀 Deploy Script - Update & Restart Minecraft Server
# ============================================================
# Usage:
#   bash deploy.sh
#
# This script:
#   1. Pulls latest changes from Git
#   2. Rebuilds Docker images
#   3. Restarts containers with zero downtime
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     🚀  Minecraft Server - Auto Deploy                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1️⃣ Pull latest from Git
echo -e "\n${BOLD}${YELLOW}📋 Step 1/4: Pulling latest changes from Git...${NC}"
if command -v git &> /dev/null && [ -d ".git" ]; then
    git pull origin $(git rev-parse --abbrev-ref HEAD)
    echo -e "${GREEN}  ✅ Git pull complete${NC}"
else
    echo -e "${RED}  ❌ Not a git repository${NC}"
    echo -e "${YELLOW}  ℹ Skipping git pull...${NC}"
fi

# 2️⃣ Install mc command if not installed
echo -e "\n${BOLD}${YELLOW}📋 Step 2/4: Updating mc command...${NC}"
if [ -f "mc.sh" ]; then
    bash mc.sh --install 2>/dev/null || true
    echo -e "${GREEN}  ✅ mc command updated${NC}"
fi

# 3️⃣ Rebuild images
echo -e "\n${BOLD}${YELLOW}📋 Step 3/4: Rebuilding Docker images...${NC}"
if [ -f "docker-compose.yml" ]; then
    docker compose pull 2>/dev/null || true
    docker compose build --no-cache 2>/dev/null || true
    echo -e "${GREEN}  ✅ Images rebuilt${NC}"
else
    echo -e "${RED}  ❌ docker-compose.yml not found${NC}"
    exit 1
fi

# 4️⃣ Restart containers
echo -e "\n${BOLD}${YELLOW}📋 Step 4/4: Restarting containers...${NC}"
docker compose up -d --force-recreate 2>/dev/null
echo -e "${GREEN}  ✅ Containers restarted${NC}"

# Show status
echo -e "\n${CYAN}  📊 Container Status:${NC}"
docker compose ps 2>/dev/null

# Cleanup old images
echo -e "\n${YELLOW}  🗑️  Cleaning up old Docker images...${NC}"
docker system prune -f 2>/dev/null || true

echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     ✅  Deploy Complete!                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  🌐  Admin Panel: ${CYAN}http://localhost:3000${NC}"
echo -e "  🎮  Minecraft:   ${CYAN}localhost:25565${NC}"