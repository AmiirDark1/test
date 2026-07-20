# ============================================================
# 🚀 Minecraft Admin Panel - Setup & Installation Script
# ============================================================
# This script installs prerequisites and starts the panel
# ============================================================

param(
    [switch]$NoDocker,
    [switch]$NoOpen
)

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

function Check-Command {
    param([string]$Command, [string]$Name)
    $exists = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Color -Color $Red -Text "❌ $Name not found! Please install $Name first."
        return $false
    }
    Write-Color -Color $Green -Text "✅ $Name detected: $($exists.Source)"
    return $true
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Color -Color $Yellow -Text "📁 Created directory: $Path"
    }
}

# ============================================================
Write-Color -Color $Magenta -Text "
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║       🚀 Minecraft Admin Panel - Setup                    ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"
Write-Color -Color $Cyan -Text "Starting setup at $(Get-Date)...`n"

# ============================================================
# 1️⃣  CHECK PREREQUISITES
# ============================================================
Write-Color -Color $Bold -Color $Yellow -Text "`n📋 Step 1/4: Checking prerequisites...`n"

$allFound = $true

# Check Node.js
if (-not (Check-Command -Command "node" -Name "Node.js")) {
    $allFound = $false
    Write-Color -Color $Yellow -Text "   ➡ Download from: https://nodejs.org/"
} else {
    $nodeVersion = node --version
    Write-Color -Color $Green -Text "   Version: $nodeVersion"
}

# Check npm
if (-not (Check-Command -Command "npm" -Name "npm")) {
    $allFound = $false
} else {
    $npmVersion = npm --version
    Write-Color -Color $Green -Text "   Version: $npmVersion"
}

# Check Docker (optional for Docker mode)
if (-not $NoDocker) {
    if (-not (Check-Command -Command "docker" -Name "Docker")) {
        Write-Color -Color $Yellow -Text "   ⚠ Docker not found - will run panel in standalone mode"
        Write-Color -Color $Yellow -Text "   ➡ Download from: https://docker.com/"
        $NoDocker = $true
    } else {
        $dockerVersion = docker --version
        Write-Color -Color $Green -Text "   Version: $dockerVersion"
    }
}

if (-not $allFound -and $NoDocker) {
    Write-Color -Color $Red -Text "`n❌ Missing required prerequisites. Please install them first."
    exit 1
}

# ============================================================
# 2️⃣  INSTALL DEPENDENCIES
# ============================================================
Write-Color -Color $Bold -Color $Yellow -Text "`n📋 Step 2/4: Installing dependencies...`n"

$panelDir = Join-Path $PSScriptRoot "mc-panel"
if (-not (Test-Path $panelDir)) {
    $panelDir = $PSScriptRoot
}

Set-Location $panelDir

if (Test-Path "package.json") {
    Write-Color -Color $Cyan -Text "📦 Installing npm packages..."
    npm install
    if ($LASTEXITCODE -eq 0) {
        Write-Color -Color $Green -Text "✅ npm dependencies installed successfully."
    } else {
        Write-Color -Color $Red -Text "❌ npm install failed!"
        exit 1
    }
} else {
    Write-Color -Color $Yellow -Text "⚠ No package.json found in current directory."
}

# ============================================================
# 3️⃣  START SERVICES
# ============================================================
Write-Color -Color $Bold -Color $Yellow -Text "`n📋 Step 3/4: Starting services...`n"

if ($NoDocker) {
    Write-Color -Color $Cyan -Text "🖥 Starting panel in standalone mode..."
    Write-Color -Color $Yellow -Text "   Make sure your Minecraft server has RCON enabled!"
    Write-Color -Color $Yellow -Text "   Edit start-panel.bat to set correct RCON settings.`n"

    # Run the panel directly with Node.js
    $serverScript = Join-Path $panelDir "server.js"
    if (Test-Path $serverScript) {
        Write-Color -Color $Green -Text "✅ Panel server starting on http://localhost:3000"
        Start-Process -FilePath "node" -ArgumentList "server.js" -NoNewWindow -WorkingDirectory $panelDir
    } else {
        Write-Color -Color $Red -Text "❌ server.js not found!"
        exit 1
    }
} else {
    Write-Color -Color $Cyan -Text "🐳 Starting containers with Docker Compose..."

    # Check if docker-compose.yml exists in root
    $composeFile = Join-Path $PSScriptRoot "docker-compose.yml"
    if (-not (Test-Path $composeFile)) {
        $composeFile = Join-Path $panelDir "..\docker-compose.yml"
    }

    Set-Location (Split-Path $composeFile -Parent)

    docker-compose up -d --build
    if ($LASTEXITCODE -eq 0) {
        Write-Color -Color $Green -Text "✅ Docker containers started successfully."
    } else {
        Write-Color -Color $Red -Text "❌ Docker Compose failed!"
        Write-Color -Color $Yellow -Text "   Trying to continue with standalone mode..."
        
        # Fallback to standalone mode
        Set-Location $panelDir
        Write-Color -Color $Cyan -Text "🖥 Starting panel in standalone mode (fallback)..."
        Start-Process -FilePath "node" -ArgumentList "server.js" -NoNewWindow -WorkingDirectory $panelDir
    }
}

# ============================================================
# 4️⃣  OPEN BROWSER
# ============================================================
Write-Color -Color $Bold -Color $Yellow -Text "`n📋 Step 4/4: Opening panel in browser...`n"

if (-not $NoOpen) {
    Write-Color -Color $Cyan -Text "🔗 Opening http://localhost:3000 in your browser..."
    Start-Process "http://localhost:3000"
}

# ============================================================
Write-Color -Color $Magenta -Text "
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║       ✅ Setup Complete!                                  ║
║                                                          ║
║   🌐 Panel URL: http://localhost:3000                     ║
║                                                          ║
║   📝 RCON Password: minecraft                             ║
║                                                          ║
║   📌 To view logs:  docker-compose logs -f                ║
║   📌 To stop:       docker-compose down                   ║
║   📌 To restart:    docker-compose restart                ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
" -Color $Green

Write-Color -Color $Green -Text "`n✅ Panel is running at: http://localhost:3000`n"