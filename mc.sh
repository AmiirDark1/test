#!/bin/bash
# ============================================================
# 🎮 mc - Minecraft Server Manager (Like msr in 3x-ui)
# ============================================================
# Usage: mc
# Install: bash mc.sh --install
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ─── INSTALL MODE ──────────────────────────────────────────────
if [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
    SCRIPT_PATH="$(realpath "$0")"
    
    # Create symlink in /usr/local/bin
    if [ -d "/usr/local/bin" ]; then
        sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/mc 2>/dev/null || {
            echo -e "${RED}  ❌ Need sudo to install. Running: sudo ln -sf ...${NC}"
            sudo ln -sf "$SCRIPT_PATH" /usr/local/bin/mc
        }
        echo -e "${GREEN}  ✅ Installed! Type '${BOLD}mc${NC}${GREEN}' anywhere in terminal.${NC}"
    elif [ -d "$HOME/.local/bin" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$SCRIPT_PATH" "$HOME/.local/bin/mc"
        echo -e "${GREEN}  ✅ Installed to ~/.local/bin/mc${NC}"
        echo -e "${YELLOW}  ⚠ Make sure ~/.local/bin is in your PATH${NC}"
    else
        # Add alias to .bashrc
        echo "alias mc='bash $SCRIPT_PATH'" >> "$HOME/.bashrc"
        echo -e "${GREEN}  ✅ Alias added to ~/.bashrc${NC}"
        echo -e "${YELLOW}  ⚠ Run: source ~/.bashrc${NC}"
    fi
    
    echo -e "${CYAN}  📌 Now just type '${BOLD}mc${NC}${CYAN}' anywhere to open the manager!${NC}"
    exit 0
fi

# ─── UNINSTALL ─────────────────────────────────────────────────
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    echo -e "${YELLOW}  🗑️  Removing mc command...${NC}"
    sudo rm -f /usr/local/bin/mc 2>/dev/null || true
    rm -f "$HOME/.local/bin/mc" 2>/dev/null || true
    sed -i "/alias mc='/d" "$HOME/.bashrc" 2>/dev/null || true
    echo -e "${GREEN}  ✅ Uninstalled.${NC}"
    exit 0
fi

# ─── DIRECT COMMANDS ───────────────────────────────────────────
if [ -n "$1" ]; then
    case "$1" in
        start)
            $COMPOSE_CMD up -d 2>/dev/null
            echo -e "${GREEN}✅ Services started${NC}"
            exit 0
            ;;
        stop)
            $COMPOSE_CMD stop 2>/dev/null
            echo -e "${GREEN}✅ Services stopped${NC}"
            exit 0
            ;;
        restart)
            docker restart minecraft 2>/dev/null || $COMPOSE_CMD restart minecraft
            echo -e "${GREEN}✅ Minecraft restarted${NC}"
            exit 0
            ;;
        status)
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -5
            exit 0
            ;;
        logs)
            docker logs -f --tail 50 minecraft 2>&1
            exit 0
            ;;
        rcon)
            docker exec -it minecraft rcon-cli 2>&1 || echo "RCON not available"
            exit 0
            ;;
        delete)
            echo -e "${RED}⚠ Use 'mc' and choose option 8 for safe deletion${NC}"
            exit 1
            ;;
        help|--help)
            echo -e "${CYAN}Usage: mc [command]${NC}"
            echo -e "  ${GREEN}(no args)${NC}  → Open interactive menu"
            echo -e "  ${GREEN}start${NC}      → Start services"
            echo -e "  ${GREEN}stop${NC}       → Stop services"
            echo -e "  ${GREEN}restart${NC}    → Restart Minecraft"
            echo -e "  ${GREEN}status${NC}     → Show container status"
            echo -e "  ${GREEN}logs${NC}       → View Minecraft logs"
            echo -e "  ${GREEN}rcon${NC}       → Open RCON console"
            echo -e "  ${GREEN}--install${NC}  → Install 'mc' command globally"
            exit 0
            ;;
    esac
fi

# ============================================================
# COMPOSE COMMAND DETECTION
# ============================================================
COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
fi

# Find project directory
PROJECT_DIR="."
find_project_dir() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/docker-compose.yml" ]; then
            PROJECT_DIR="$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    # Check common locations
    for loc in "$HOME/mc-server-panel" "$HOME/mc-panel" "/opt/mc-server-panel"; do
        if [ -f "$loc/docker-compose.yml" ]; then
            PROJECT_DIR="$loc"
            return 0
        fi
    done
    return 1
}
find_project_dir 2>/dev/null || true
cd "$PROJECT_DIR" 2>/dev/null || true

# ============================================================
# FUNCTIONS
# ============================================================

show_header() {
    clear
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo -e "║     ${BOLD}🎮  Minecraft Server Manager${NC}${MAGENTA}                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_status() {
    echo -e "\n${BOLD}${CYAN}📊 Container Status:${NC}"
    
    if [ -n "$COMPOSE_CMD" ]; then
        $COMPOSE_CMD ps 2>/dev/null || echo -e "${RED}  Containers not running${NC}"
    else
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo -e "${RED}  No containers found${NC}"
    fi
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "minecraft"; then
        local uptime=$(docker inspect --format='{{.State.StartedAt}}' minecraft 2>/dev/null | cut -d'.' -f1 | tr 'T' ' ')
        local mem=$(docker stats --no-stream --format '{{.MemUsage}}' minecraft 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}  ✅ Minecraft: running | RAM: ${mem} | Since: ${uptime}${NC}"
    else
        echo -e "${RED}  ❌ Minecraft: STOPPED${NC}"
    fi
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "mc-admin-panel"; then
        echo -e "${GREEN}  ✅ Admin Panel: running | http://localhost:3000${NC}"
    else
        echo -e "${RED}  ❌ Admin Panel: STOPPED${NC}"
    fi
}

view_logs() {
    echo -e "\n${BOLD}${YELLOW}📋 Select logs:${NC}"
    echo -e "  ${CYAN}1)${NC} Minecraft server"
    echo -e "  ${CYAN}2)${NC} Admin panel"
    echo -e "  ${CYAN}3)${NC} Back"
    echo -ne "\n${BOLD}Choice [1-3]:${NC} "
    read -r log_choice
    
    case "$log_choice" in
        1) 
            echo -e "\n${YELLOW}📋 Minecraft logs (Ctrl+C to exit)${NC}"
            sleep 1
            docker logs -f --tail 50 minecraft 2>&1 || echo -e "${RED}No logs${NC}"
            echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
            ;;
        2)
            echo -e "\n${YELLOW}📋 Panel logs (Ctrl+C to exit)${NC}"
            sleep 1
            docker logs -f --tail 50 mc-admin-panel 2>&1 || echo -e "${RED}No logs${NC}"
            echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
            ;;
    esac
}

rcon_console() {
    echo -e "\n${BOLD}${GREEN}🔧 RCON Console${NC}"
    
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "minecraft"; then
        echo -e "${RED}  ❌ Minecraft is not running!${NC}"
        echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
        return
    fi
    
    echo -e "${YELLOW}  Commands: help, list, say <msg>, gamemode <g> <p>, stop, time set <t>${NC}"
    echo -e "${YELLOW}  Type 'exit' to return${NC}\n"
    
    local rcon_pass="minecraft"
    [ -f "docker-compose.yml" ] && rcon_pass=$(grep -oP 'RCON_PASSWORD:\s*"\K[^"]+' docker-compose.yml 2>/dev/null || echo "minecraft")
    
    while true; do
        echo -ne "${GREEN}RCON >${NC} "
        read -r cmd
        [ "$cmd" = "exit" ] || [ "$cmd" = "q" ] && break
        [ -n "$cmd" ] && docker exec minecraft rcon-cli --password "$rcon_pass" --port 25575 "$cmd" 2>&1 || \
            echo -e "${RED}  RCON failed${NC}"
    done
}

restart_server() {
    echo -e "\n${BOLD}${YELLOW}🔄 Restarting Minecraft...${NC}"
    docker exec minecraft rcon-cli --password minecraft --port 25575 "say §cServer restarting in 10s..." 2>/dev/null || true
    sleep 2
    docker restart minecraft 2>/dev/null || $COMPOSE_CMD restart minecraft 2>/dev/null
    sleep 3
    echo -e "${GREEN}  ✅ Minecraft restarted!${NC}"
    echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
}

stop_server() {
    echo -e "\n${BOLD}${RED}🛑 Stopping all services...${NC}"
    docker exec minecraft rcon-cli --password minecraft --port 25575 "say §c§lSERVER SHUTTING DOWN!" 2>/dev/null || true
    sleep 2
    $COMPOSE_CMD stop 2>/dev/null || docker stop minecraft mc-admin-panel 2>/dev/null || true
    echo -e "${GREEN}  ✅ All services stopped${NC}"
    echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
}

start_server() {
    echo -e "\n${BOLD}${GREEN}▶️  Starting services...${NC}"
    $COMPOSE_CMD start 2>/dev/null || $COMPOSE_CMD up -d 2>/dev/null || echo -e "${RED}  ❌ Failed${NC}"
    echo -e "${GREEN}  ✅ Services started${NC}"
    echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
}

delete_server() {
    echo -e "\n${BOLD}${RED}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              ☠  DELETE EVERYTHING                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${RED}  ⚠ Permanently deletes: containers, images, worlds, plugins${NC}\n"
    
    echo -ne "${YELLOW}  Type 'yes' to continue: ${NC}"
    read -r c1; [ "$c1" != "yes" ] && { echo -e "${GREEN}Cancelled${NC}"; echo -e "\n${YELLOW}Press Enter...${NC}" && read -r; return; }
    
    echo -ne "${RED}  Type 'DELETE ALL DATA' to confirm: ${NC}"
    read -r c2; [ "$c2" != "DELETE ALL DATA" ] && { echo -e "${GREEN}Cancelled${NC}"; echo -e "\n${YELLOW}Press Enter...${NC}" && read -r; return; }
    
    echo -e "\n${YELLOW}  🗑️  Deleting...${NC}"
    $COMPOSE_CMD down -v 2>/dev/null || true
    docker rm -f minecraft mc-admin-panel 2>/dev/null || true
    docker rmi mc-admin-panel:latest 2>/dev/null || true
    [ -d "data" ] && rm -rf data && echo -e "${YELLOW}  🗑️  Data removed${NC}"
    
    echo -e "\n${RED}  Remove project files too?${NC}"
    echo -ne "${CYAN}  Type 'remove' to delete everything: ${NC}"
    read -r rp
    if [ "$rp" = "remove" ]; then
        cd /tmp
        rm -rf "$PROJECT_DIR" 2>/dev/null || true
        echo -e "${GREEN}  ✅ Project files removed${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}  ✅ Server deleted. Data kept at: $PROJECT_DIR/data${NC}"
    echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
}

system_info() {
    echo -e "\n${BOLD}${CYAN}📊 System Info${NC}"
    [ -d "data" ] && echo -e "  💾 Data size: $(du -sh data 2>/dev/null | cut -f1)"
    echo -e "  🐳 Docker:" && docker system df 2>/dev/null | head -3
    echo -e "\n${CYAN}  Minecraft Containers:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -1
    for c in minecraft mc-admin-panel; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$c$"; then
            docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $c 2>/dev/null
        fi
    done
    echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
}

# ============================================================
# MAIN LOOP
# ============================================================
while true; do
    show_header
    show_status
    
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1)${NC} ▶  Start"
    echo -e "  ${RED}2)${NC} ⏹  Stop"
    echo -e "  ${YELLOW}3)${NC} 🔄 Restart Minecraft"
    echo -e "  ${CYAN}4)${NC} 📋 Logs"
    echo -e "  ${GREEN}5)${NC} 💬 RCON Console"
    echo -e "  ${CYAN}6)${NC} 📊 System info"
    echo -e "  ${MAGENTA}7)${NC} 🏗️  Rebuild & restart"
    echo -e "  ${BLUE}9)${NC} 🚀 Deploy (git pull + rebuild)"
    echo -e "  ${RED}8)${NC} ☠  Delete server"
    echo -e "  ${BOLD}0)${NC} 🚪 Exit"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
            echo -e "\n${YELLOW}🏗️  Rebuilding...${NC}"
            docker build -t mc-admin-panel:latest ./mc-panel 2>/dev/null || true
            $COMPOSE_CMD up -d --force-recreate 2>/dev/null
            echo -e "${GREEN}  ✅ Done${NC}" && echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
            ;;
        8) delete_server ;;
        9)
            if [ -f "deploy.sh" ]; then
                bash deploy.sh
            else
                echo -e "\n${YELLOW}🚀 Deploying...${NC}"
                git pull origin $(git rev-parse --abbrev-ref HEAD) 2>/dev/null || echo -e "${YELLOW}  ⚠ Git pull failed, skipping${NC}"
                docker compose build --no-cache 2>/dev/null || true
                docker compose up -d --force-recreate 2>/dev/null
                echo -e "${GREEN}  ✅ Deploy complete${NC}"
            fi
            echo -e "\n${YELLOW}Press Enter...${NC}" && read -r
            ;;
        0) echo -e "\n${GREEN}👋${NC}" && exit 0 ;;
        *) echo -e "\n${RED}❌ Invalid${NC}" && sleep 1 ;;
    esac
done