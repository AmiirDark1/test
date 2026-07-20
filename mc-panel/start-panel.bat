@echo off
chcp 65001 >nul
title 🚀 Minecraft Admin Panel
cd /d "%~dp0"

echo ╔══════════════════════════════════════════════════════════╗
echo ║                                                          ║
echo ║       🚀 Minecraft Admin Panel - Starting...              ║
echo ║                                                          ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

:: Check Node.js
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Node.js is not installed!
    echo Please install Node.js from: https://nodejs.org/
    pause
    exit /b 1
)
echo [OK] Node.js found: 
node --version

:: Check npm
where npm >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] npm is not installed!
    pause
    exit /b 1
)
echo [OK] npm found:
npm --version

:: Install dependencies if needed
if not exist "node_modules\" (
    echo.
    echo [INFO] Installing dependencies...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] npm install failed!
        pause
        exit /b 1
    )
    echo [OK] Dependencies installed.
)

:: Set RCON Configuration
set RCON_HOST=127.0.0.1
set RCON_PORT=25575
set RCON_PASSWORD=minecraft
set SERVER_PORT=3000

echo.
echo [INFO] Starting MC Panel on http://localhost:3000
echo [INFO] RCON: %RCON_HOST%:%RCON_PORT%
echo.

:: Start the panel server
node server.js

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Panel exited with error code %ERRORLEVEL%
    pause
)