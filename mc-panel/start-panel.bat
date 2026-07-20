@echo off
cd /d "%~dp0"
set RCON_HOST=127.0.0.1
set RCON_PORT=25575
set RCON_PASSWORD=minecraft
set SERVER_PORT=3000
echo Starting MC Panel on http://localhost:3000
node server.js