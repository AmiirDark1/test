# ============================================================
# 🚀 Minecraft Server + Admin Panel - Full Project Setup
# ============================================================
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/AmiirDark1/test/master/setup.ps1 | iex
# ============================================================

param([switch]$NoOpen)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Green = "`e[32m"
$Yellow = "`e[33m"
$Red = "`e[31m"
$Cyan = "`e[36m"
$Magenta = "`e[35m"
$Reset = "`e[0m"
$Bold = "`e[1m"

function Write-Color {
    param([string]$Color, [string]$Text)
    Write-Host "$Color$Text$Reset"
}

function Write-Step {
    param([string]$Number, [string]$Title)
    Write-Color -Color $Bold -Color $Yellow -Text "`n📋 Step ${Number}: ${Title}"
    Write-Host "─" * 50
}

function Check-Command {
    param([string]$Command, [string]$Name, [string]$Url)
    $exists = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Color -Color $Red -Text "  ❌ $Name not found!"
        if ($Url) {
            Write-Color -Color $Yellow -Text "     ➡ Download: $Url"
        }
        return $false
    }
    Write-Color -Color $Green -Text "  ✅ $Name found at $($exists.Source)"
    return $true
}

# ============================================================
Clear-Host
Write-Color -Color $Magenta -Text "
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     🚀  Minecraft Server + Admin Panel                        ║
║         Full Project Setup Script                             ║
║                                                              ║
║     📦 Docker Edition                                         ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
"
Write-Color -Color $Cyan -Text "  Starting setup at $(Get-Date)...`n"

# ============================================================
# 1️⃣  CHECK PREREQUISITES
# ============================================================
Write-Step -Number "1/5" -Title "Checking & Installing Docker..."

$dockerOk = Check-Command -Command "docker" -Name "Docker"
$composeOk = Check-Command -Command "docker-compose" -Name "Docker Compose"

if (-not $dockerOk) {
    Write-Color -Color $Yellow -Text "  ⏳ Docker not found. Please install Docker Desktop from:"
    Write-Color -Color $Cyan -Text "     https://www.docker.com/products/docker-desktop/"
    Write-Color -Color $Red -Text "  ❌ Docker is required. Install and re-run this script."
    exit 1
}

if (-not $composeOk) {
    $dockerComposeV2 = docker compose version --short 2>$null
    if ($dockerComposeV2) {
        Write-Color -Color $Green -Text "  ✅ Docker Compose (v2): $dockerComposeV2"
        $composeOk = $true
        $global:UseComposeV2 = $true
    }
}

if (-not $composeOk) {
    Write-Color -Color $Red -Text "  ❌ Docker Compose not found. Install and re-run."
    exit 1
}

Write-Color -Color $Cyan -Text "  🔍 Checking Docker daemon..."
try {
    docker info 2>&1 | Out-Null
    Write-Color -Color $Green -Text "  ✅ Docker daemon is running"
} catch {
    Write-Color -Color $Red -Text "  ❌ Docker daemon is NOT running! Start Docker Desktop."
    exit 1
}

# ============================================================
# 2️⃣  GET PROJECT FILES
# ============================================================
Write-Step -Number "2/5" -Title "Getting project files..."

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $scriptPath

# Check if we're in the right place
if (-not (Test-Path (Join-Path $projectRoot "docker-compose.yml"))) {
    Write-Color -Color $Yellow -Text "  ⏳ Project files not found. Cloning from GitHub..."
    
    # Check if git is available
    $gitOk = Get-Command git -ErrorAction SilentlyContinue
    if ($gitOk) {
        git clone --depth 1 "https://github.com/AmiirDark1/test.git" "mc-server-panel" 2>&1 | Out-Null
        if (Test-Path "mc-server-panel") {
            Set-Location "mc-server-panel"
            $projectRoot = Get-Location
        }
    }
    
    # Try download as zip if git failed
    if (-not (Test-Path (Join-Path $projectRoot "docker-compose.yml"))) {
        Write-Color -Color $Yellow -Text "  ⏳ Downloading as zip..."
        $zipPath = Join-Path $env:TEMP "mc-panel.zip"
        $extractPath = Join-Path $env:TEMP "mc-panel-extracted"
        Invoke-WebRequest -Uri "https://github.com/AmiirDark1/test/archive/master.zip" -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $extracted = Get-ChildItem $extractPath -Directory | Select-Object -First 1
        if ($extracted) {
            Copy-Item "$($extracted.FullName)\*" -Destination $projectRoot -Recurse -Force
        }
    }
}

if (-not (Test-Path (Join-Path $projectRoot "docker-compose.yml"))) {
    Write-Color -Color $Red -Text "  ❌ Could not get project files!"
    exit 1
}

Set-Location $projectRoot
Write-Color -Color $Green -Text "  ✅ Project files ready"

# ============================================================
# 3️⃣  SETUP DATA & BUILD
# ============================================================
Write-Step -Number "3/5" -Title "Setting up data & building images..."

$dataDir = Join-Path $projectRoot "data"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

foreach ($dir in @("world","world_nether","world_the_end","plugins","logs","cache")) {
    New-Item -ItemType Directory -Path (Join-Path $dataDir $dir) -Force | Out-Null
}
Write-Color -Color $Green -Text "  ✅ Data directories created"

Write-Color -Color $Cyan -Text "  🏗️ Building panel image..."
docker build -t mc-admin-panel:latest ./mc-panel
if ($LASTEXITCODE -eq 0) {
    Write-Color -Color $Green -Text "  ✅ Panel image built"
} else {
    Write-Color -Color $Red -Text "  ❌ Build failed!"
    exit 1
}

# ============================================================
# 4️⃣  START CONTAINERS
# ============================================================
Write-Step -Number "4/5" -Title "Starting containers..."

Write-Color -Color $Cyan -Text "  🐳 Starting services..."
Write-Color -Color $Yellow -Text "     🟢 Minecraft → port 25565"
Write-Color -Color $Yellow -Text "     🔵 RCON      → port 25575"
Write-Color -Color $Yellow -Text "     🟣 Panel     → port 3000`n"

if ($global:UseComposeV2) {
    docker compose up -d --build
} else {
    docker-compose up -d --build
}

if ($LASTEXITCODE -eq 0) {
    Write-Color -Color $Green -Text "  ✅ Containers started`n"
} else {
    Write-Color -Color $Red -Text "  ❌ Failed!"
    exit 1
}

# ============================================================
# 5️⃣  WAIT & SHOW INFO
# ============================================================
Write-Step -Number "5/5" -Title "Waiting for Minecraft server..."

Write-Color -Color $Cyan -Text "  ⏳ This may take a minute..."
$maxWait = 120
$waited = 0
$ready = $false

while ($waited -lt $maxWait) {
    $logs = docker logs minecraft 2>&1
    if ($logs -match "Done \(") {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
    if ($waited % 10 -eq 0) {
        Write-Color -Color $Yellow -Text "     Waiting... ($waited seconds)"
    }
}

if ($ready) {
    Write-Color -Color $Green -Text "  ✅ Minecraft server is ready!"
} else {
    Write-Color -Color $Yellow -Text "  ⚠ Timeout. Check: docker logs minecraft"
}

Write-Color -Color $Cyan -Text "`n  📊 Container Status:"
if ($global:UseComposeV2) { docker compose ps } else { docker-compose ps }

# ============================================================
Write-Color -Color $Magenta -Text "
╔══════════════════════════════════════════════════════════════╗
║       ✅  SETUP COMPLETE!                                     ║
║   🌐  Panel:   http://localhost:3000                          ║
║   🎮  Server:  localhost:25565                                ║
║   🔧  RCON:    localhost:25575 / pass: minecraft              ║
╚══════════════════════════════════════════════════════════════╝
"

if (-not $NoOpen) {
    Write-Color -Color $Cyan -Text "  🔗 Opening panel..."
    Start-Process "http://localhost:3000"
}

Write-Color -Color $Green -Text "`n  ✅ Done! Panel: http://localhost:3000`n"