#!/bin/bash
# نصب و راه‌اندازی Minecraft Panel روی لینوکس
echo "📦 Building and starting containers..."
docker-compose up -d --build

echo ""
echo "✅ Panel is running!"
echo "   Minecraft Server : localhost:25565"
echo "   Panel (Web UI)   : http://localhost:3000"
echo ""
echo "📝 RCON Password: minecraft"
echo ""
echo "To see logs: docker-compose logs -f"
echo "To stop:     docker-compose down"