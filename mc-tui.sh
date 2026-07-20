#!/bin/bash
# ============================================================
# 🎮 Minecraft Server Manager - Terminal UI
# ============================================================
# Usage:
#   bash mc-tui.sh
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    echo -e "${RED}❌ Docker Compose not found!${NC}"
    exit 1
fi

PROJECT_DIR="."

# Find the docker-compose.yml
if [ ! -f "docker-compose.yml" ]; then
    if [ "$(basename "$PWD")" = "mc-server-panel" ] || [ "$(basename "$PWD")" = "mc-panel" ]; then
        if [ -f "../docker-compose.yml" ]; then
            PROJECT_DIR=".."
        fi
    fi
    # Search upward
    DIR="$PWD"
    while [ "$DIR" != "/" ]; do
        if [ -f "$DIR/docker-compose.yml" ]; then
            PROJECT_DIR="$DIR"
            break
        fi
        DIR="$(dirname "$DIR")"
    done
fi

cd "$PROJECT_DIR"

clear
echo -e "${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║     🎮  Minecraft Server Manager                             ║"
echo "║         Terminal Control Panel                               ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# --------------------------------------------------
# SHOW STATUS
# --------------------------------------------------
show_status() {
    echo -e "\n${BOLD}${CYAN}📊 Container Status:${NC}"
    if [ "$COMPOSE_CMD" = "docker compose" ]; then
        docker compose ps 2>/dev/null || echo -e "${RED}  Containers not running${NC}"
    else
        docker-compose ps 2>/dev/null || echo -e "${RED}  Containers not running${NC}"
    fi
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "minecraft"; then
        local uptime=$(docker inspect --format='{{.State.StartedAt}}' minecraft 2>/dev/null | cut -d'.' -f1 | tr 'T' ' ')
        local status=$(docker inspect --format='{{.State.Status}}' minecraft 2>/dev/null)
        local mem=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}  ✅ Minecraft: ${status} | Mem: ${mem} | Since: ${uptime}${NC}"
    else
        echo -e "${RED}  ❌ Minecraft: STOPPED${NC}"
    fi
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "mc-admin-panel"; then
        local uptime=$(docker inspect --format='{{.State.StartedAt}}' mc-admin-panel 2>/dev/null | cut -d'.' -f1 | tr 'T' ' ')
        echo -e "${GREEN}  ✅ Panel: running | Since: ${uptime}${NC}"
    else
        echo -e "${RED}  ❌ Panel: STOPPED${NC}"
    fi
}

# --------------------------------------------------
# VIEW LOGS
# --------------------------------------------------
view_logs() {
    echo -e "\n${BOLD}${YELLOW}📋 Select logs to view:${NC}"
    echo -e "  ${CYAN}1)${NC} Minecraft server logs"
    echo -e "  ${CYAN}2)${NC} Admin panel logs"
    echo -e "  ${CYAN}3)${NC} Back to menu"
    echo -ne "\n${BOLD}Choice [1-3]:${NC} "
    read -r log_choice
    
    case "$log_choice" in
        1) 
            echo -e "\n${YELLOW}📋 Minecraft logs (Ctrl+C to exit back to menu)${NC}"
            sleep 1
            docker logs -f --tail 50 minecraft 2>&1 || echo -e "${RED}No logs available${NC}"
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read -r
            ;;
        2)
            echo -e "\n${YELLOW}📋 Admin panel logs (Ctrl+C to exit back to menu)${NC}"
            sleep 1
            docker logs -f --tail 50 mc-admin-panel 2>&1 || echo -e "${RED}No logs available${NC}"
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read -r
            ;;
    esac
}

# --------------------------------------------------
# RCON CONSOLE
# --------------------------------------------------
rcon_console() {
    echo -e "\n${BOLD}${GREEN}🔧 RCON Console${NC}"
    echo -e "${YELLOW}  Commands: help, list, say <msg>, gamemode <g> <player>, stop, time set <t>, weather <type>${NC}"
    echo -e "${YELLOW}  Type 'exit' to return to menu${NC}"
    echo ""
    
    # Check if RCON is available
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "minecraft"; then
        echo -e "${RED}  ❌ Minecraft server is not running!${NC}"
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    # Check if rcon-cli is available in container
    docker exec minecraft which rcon-cli &>/dev/null || {
        echo -e "${YELLOW}  ⚠ Installing rcon-cli in container...${NC}"
        docker exec minecraft bash -c "apt-get update -qq && apt-get install -y -qq rcon-cli 2>/dev/null || true"
    }
    
    local rcon_pass="minecraft"
    # Try to get password from docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        local pass_from_config=$(grep -oP 'RCON_PASSWORD:\s*"\K[^"]+' docker-compose.yml 2>/dev/null || grep -oP 'RCON_PASSWORD=\K[^ ]+' docker-compose.yml 2>/dev/null || echo "minecraft")
        rcon_pass="$pass_from_config"
    fi
    
    local running=true
    while $running; do
        echo -ne "${GREEN}RCON >${NC} "
        read -r cmd
        if [ "$cmd" = "exit" ] || [ "$cmd" = "quit" ] || [ "$cmd" = "q" ]; then
            running=false
        elif [ -n "$cmd" ]; then
            docker exec minecraft rcon-cli --password "$rcon_pass" --port 25575 "$cmd" 2>&1 || \
            echo -e "${RED}  RCON command failed. Try: docker exec -it minecraft rcon-cli${NC}"
        fi
    done
}

# --------------------------------------------------
# RESTART SERVER
# --------------------------------------------------
restart_server() {
    echo -e "\n${BOLD}${YELLOW}🔄 Restarting Minecraft server...${NC}"
    
    # Warn players via RCON
    docker exec minecraft rcon-cli --password minecraft --port 25575 "say §cServer will restart in 10 seconds..." 2>/dev/null || true
    
    echo -e "${YELLOW}  ⏳ Restarting container...${NC}"
    docker restart minecraft 2>/dev/null || {
        $COMPOSE_CMD restart minecraft 2>/dev/null || {
            $COMPOSE_CMD up -d --force-recreate minecraft 2>/dev/null
        }
    }
    
    sleep 3
    echo -e "${GREEN}  ✅ Server restarted!${NC}"
    echo -e "${YELLOW}\nPress Enter to continue...${NC}"
    read -r
}

# --------------------------------------------------
# STOP SERVER
# --------------------------------------------------
stop_server() {
    echo -e "\n${BOLD}${RED}🛑 Stopping all services...${NC}"
    echo -e "${YELLOW}  ⚠ This will kick all players!${NC}"
    
    # Warn players via RCON
    docker exec minecraft rcon-cli --password minecraft --port 25575 "say §c§lServer is shutting down NOW!" 2>/dev/null || true
    sleep 2
    
    $COMPOSE_CMD stop 2>/dev/null || {
        docker stop minecraft mc-admin-panel 2>/dev/null || true
    }
    echo -e "${GREEN}  ✅ All services stopped${NC}"
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --------------------------------------------------
# START SERVER
# --------------------------------------------------
start_server() {
    echo -e "\n${BOLD}${GREEN}▶️  Starting all services...${NC}"
    $COMPOSE_CMD start 2>/dev/null || {
        $COMPOSE_CMD up -d 2>/dev/null || {
            echo -e "${RED}  ❌ Failed to start${NC}"
        }
    }
    echo -e "${GREEN}  ✅ Services started${NC}"
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --------------------------------------------------
# DELETE SERVER (with confirmation)
# --------------------------------------------------
delete_server() {
    echo -e "\n${BOLD}${RED}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     ☠  DANGER ZONE - DELETE EVERYTHING!                     ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${RED}  ⚠ This will PERMANENTLY DELETE:${NC}"
    echo -e "     • All containers and images"
    echo -e "     • All server data (worlds, plugins, logs)"
    echo -e "     • The admin panel"
    echo -e "     • Docker volumes${NC}"
    echo ""
    
    # First confirmation
    echo -ne "${YELLOW}  Are you sure? Type 'yes' to continue: ${NC}"
    read -r confirm1
    if [ "$confirm1" != "yes" ]; then
        echo -e "${GREEN}  ✅ Cancelled.${NC}"
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    # Second confirmation
    echo -e "\n${RED}  ⚠ FINAL WARNING: This cannot be undone!${NC}"
    echo -ne "${YELLOW}  Type 'DELETE ALL DATA' (exactly) to proceed: ${NC}"
    read -r confirm2
    if [ "$confirm2" != "DELETE ALL DATA" ]; then
        echo -e "${GREEN}  ✅ Cancelled.${NC}"
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r
        return
    fi
    
    echo -e "\n${YELLOW}  🗑️  Deleting everything...${NC}"
    
    # Stop and remove containers
    $COMPOSE_CMD down -v 2>/dev/null || true
    
    # Remove the specific containers if still there
    docker rm -f minecraft mc-admin-panel 2>/dev/null || true
    
    # Remove the images
    docker rmi mc-admin-panel:latest 2>/dev/null || true
    
    # Remove data directory
    if [ -d "data" ]; then
        echo -e "${YELLOW}  🗑️  Removing data directory (worlds, plugins, etc)...${NC}"
        rm -rf data
    fi
    
    # Ask about removing the project directory
    echo ""
    echo -e "${YELLOW}  Remove all project files (docker-compose.yml, mc-panel, etc)?${NC}"
    echo -ne "${CYAN}  Type 'remove' to delete project files, or anything else to skip: ${NC}"
    read -r remove_project
    if [ "$remove_project" = "remove" ]; then
        cd "$(dirname "$PROJECT_DIR/..")"
        rm -rf "$PROJECT_DIR" 2>/dev/null || true
        echo -e "${GREEN}  ✅ Project files removed.${NC}"
        echo -e "${YELLOW}  ℹ Exiting... (current directory is gone)${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}  ✅ Minecraft server fully uninstalled!${NC}"
    echo -e "${YELLOW}  📁 Data directory kept at: $(pwd)/data${NC}"
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --------------------------------------------------
# SYSTEM INFO
# --------------------------------------------------
system_info() {
    echo -e "\n${BOLD}${CYAN}📊 System Information:${NC}"
    
    # Disk usage
    if [ -d "data" ]; then
        local data_size=$(du -sh data 2>/dev/null | cut -f1)
        echo -e "  💾 Server data size: ${GREEN}$data_size${NC}"
    fi
    
    # Docker disk usage
    echo -e "  🐳 Docker disk usage:"
    docker system df 2>/dev/null | head -5
    
    # Container resource usage
    echo -e "\n${CYAN}  Minecraft Containers:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | head -1
    for c in minecraft mc-admin-panel; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$c$"; then
            docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $c 2>/dev/null
        fi
    done
    
    # Port usage
    echo -e "\n${CYAN}  Port Check:${NC}"
    if command -v ss &> /dev/null; then
        ss -tlnp | grep -E '25565|25575|3000' 2>/dev/null || echo -e "${YELLOW}  Ports not in use${NC}"
    elif command -v netstat &> /dev/null; then
        netstat -tlnp 2>/dev/null | grep -E '25565|25575|3000' || echo -e "${YELLOW}  Ports not in use${NC}"
    fi
    
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# --------------------------------------------------
# MAIN MENU
# --------------------------------------------------
while true; do
    clear
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo -e "║     ${BOLD}🎮  Minecraft Server Manager${NC}${MAGENTA}                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    show_status
    
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}📋 Menu:${NC}"
    echo -e "  ${GREEN}1)${NC} ▶  Start all services"
    echo -e "  ${RED}2)${NC} ⏹  Stop all services"
    echo -e "  ${YELLOW}3)${NC} 🔄 Restart Minecraft server"
    echo -e "  ${CYAN}4)${NC} 📋 View logs"
    echo -e "  ${GREEN}5)${NC} 💬 RCON Console"
    echo -e "  ${CYAN}6)${NC} 📊 System info"
    echo -e "  ${MAGENTA}7)${NC} 🏗️  Rebuild & restart"
    echo -e "  ${RED}8)${NC} ☠  Delete everything"
    echo -e "  ${BOLD}0)${NC} 🚪 Exit"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -ne "\n${BOLD}Choice [0-8]:${NC} "
    read -r choice
    
    case "$choice" in
        1) start_server ;;
        2) stop_server ;;
        3) restart_server ;;
        4) view_logs ;;
        5) rcon_console ;;
        6) system_info ;;
        7)
            echo -e "\n${BOLD}${YELLOW}🏗️  Rebuilding and restarting...${NC}"
            docker build -t mc-admin-panel:latest ./mc-panel 2>/dev/null || echo -e "${YELLOW}  ⚠ Panel dir not found, skipping build${NC}"
            $COMPOSE_CMD up -d --force-recreate 2>/dev/null
            echo -e "${GREEN}  ✅ Done!${NC}"
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read -r
            ;;
        8) delete_server ;;
        0)
            echo -e "\n${GREEN}👋 Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}❌ Invalid choice!${NC}"
            sleep 1
            ;;
    esac
done