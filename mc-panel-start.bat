@echo off
chcp 65001 >nul
title 🚀 Minecraft Server Panel - Setup
cls

echo ============================================================
echo.
echo    🚀  Minecraft Server Panel
echo        Setup Script (Windows Version)
echo.
echo ============================================================
echo.

:: ============================================================
:: 1️⃣  CHECK PREREQUISITES
:: ============================================================
echo [1/4] Checking prerequisites...

:: Check Docker
where docker >nul 2>&1
if %errorlevel% equ 0 (
    echo   ✅ Docker: found
) else (
    echo   ❌ Docker is not installed!
    echo   Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/
    echo   After installation, run this script again.
    pause
    exit /b 1
)

:: Check Docker Compose
where docker-compose >nul 2>&1
if %errorlevel% equ 0 (
    echo   ✅ Docker Compose: found
) else (
    :: Check if Docker has built-in compose v2
    docker compose version >nul 2>&1
    if %errorlevel% equ 0 (
        echo   ✅ Docker Compose v2: found
    ) else (
        echo   ⚠ Docker Compose not found. Will use "docker compose" if available.
    )
)

echo.
echo   ✅ All prerequisites found!
echo.

:: ============================================================
:: 2️⃣  SETUP PROJECT
:: ============================================================
echo [2/4] Setting up project...

:: Check if project files exist
if exist docker-compose.yml (
    echo   ✅ Project files found in current directory
) else (
    echo   📥 Project files not found. Downloading from GitHub...
    where git >nul 2>&1
    if %errorlevel% equ 0 (
        git clone --depth 1 https://github.com/AmiirDark1/test.git mc-server-panel
        if exist mc-server-panel (
            cd mc-server-panel
            echo   ✅ Project cloned successfully
        ) else (
            echo   ❌ Failed to clone repository
            pause
            exit /b 1
        )
    ) else (
        echo   ❌ Git not found. Please install Git from: https://git-scm.com/
        pause
        exit /b 1
    )
)

:: ============================================================
:: 3️⃣  CREATE DATA DIRECTORIES
:: ============================================================
echo [3/4] Creating data directories...

if not exist data mkdir data
if not exist data\world mkdir data\world
if not exist data\world_nether mkdir data\world_nether
if not exist data\world_the_end mkdir data\world_the_end
if not exist data\plugins mkdir data\plugins
if not exist data\logs mkdir data\logs
if not exist data\cache mkdir data\cache
echo   ✅ Data directories created

:: Build panel image
echo.
echo   🏗️ Building admin panel image...
docker build -t mc-admin-panel:latest ./mc-panel
echo   ✅ Panel image built

echo.

:: ============================================================
:: 4️⃣  START SERVICES
:: ============================================================
echo [4/4] Starting services...

:: Stop existing containers
echo   🛑 Stopping any existing services...
docker-compose down 2>nul || docker compose down 2>nul

:: Start containers
echo   🐳 Starting containers...
docker-compose up -d --build 2>nul || docker compose up -d --build
if %errorlevel% equ 0 (
    echo   ✅ Containers started
) else (
    echo   ❌ Failed to start containers
    pause
    exit /b 1
)

:: Show status
echo.
echo   📊 Container Status:
docker-compose ps 2>nul || docker compose ps

echo.

:: ============================================================
:: ✅ DONE
:: ============================================================
echo ============================================================
echo.
echo       ✅  SETUP COMPLETE!
echo.
echo   🌐  Admin Panel:  http://localhost:3000
echo   🎮  Minecraft:    localhost:25565
echo   🔧  RCON:         localhost:25575 / password: minecraft
echo.
echo   📁  Server Data:  %cd%\data\
echo.
echo ============================================================
echo.

:: Open browser
echo   🔗 Opening panel in browser...
start http://localhost:3000

echo.
echo   ✅ Panel is now running at: http://localhost:3000
echo.
echo   📌 Useful Commands:
echo      docker-compose logs -f   → View all logs
echo      docker-compose down      → Stop all services
echo      docker-compose restart   → Restart services
echo.
pause