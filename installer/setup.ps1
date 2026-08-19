#Requires -Version 5.1
<#
.SYNOPSIS
    Super Sistema — Установщик для Windows
.DESCRIPTION
    Устанавливает Super Sistema (Open WebUI + Ollama) через Docker Desktop.
    Работает полностью локально без облаков.
.NOTES
    Запуск: Правая кнопка → "Запустить с правами администратора"
    Или в PowerShell (от администратора):
        Set-ExecutionPolicy Bypass -Scope Process -Force
        .\setup.ps1
#>

param(
    [string]$InstallDir = "$env:USERPROFILE\super-sistema",
    [int]$WebUIPort = 3000,
    [switch]$NoModel,
    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Цвета и вывод ────────────────────────────────────────────────────────────
function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       SUPER SISTEMA — Установка Windows v1.0        ║" -ForegroundColor Cyan
    Write-Host "║      Локальный AI-ассистент без облаков              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step   { param($msg) Write-Host "`n▶ $msg" -ForegroundColor Yellow }
function Write-OK     { param($msg) Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Info   { param($msg) Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
function Write-Warn   { param($msg) Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail   { param($msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

# ─── Проверка прав администратора ────────────────────────────────────────────
function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─── Проверить версию Windows ─────────────────────────────────────────────────
function Test-WindowsVersion {
    $version = [System.Environment]::OSVersion.Version
    if ($version.Major -lt 10) {
        Write-Fail "Требуется Windows 10 или новее (обнаружена версия $($version.Major).$($version.Minor))"
        exit 1
    }
    Write-OK "Windows $($version.Major).$($version.Minor) — поддерживается"
}

# ─── Проверить и включить WSL2 ───────────────────────────────────────────────
function Enable-WSL2 {
    Write-Step "Проверка WSL2..."

    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -ErrorAction SilentlyContinue
    $vmFeature  = Get-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -ErrorAction SilentlyContinue

    $needReboot = $false

    if ($wslFeature.State -ne "Enabled") {
        Write-Info "Включаем подсистему WSL..."
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart | Out-Null
        $needReboot = $true
    }

    if ($vmFeature.State -ne "Enabled") {
        Write-Info "Включаем виртуализацию (VirtualMachinePlatform)..."
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart | Out-Null
        $needReboot = $true
    }

    if ($needReboot) {
        Write-Warn "Необходима перезагрузка для активации WSL2."
        Write-Warn "После перезагрузки запустите этот скрипт снова."
        if (-not $Silent) {
            $choice = Read-Host "Перезагрузить сейчас? (y/N)"
            if ($choice -eq "y" -or $choice -eq "Y") {
                Restart-Computer -Force
            }
        }
        exit 0
    }

    # Установить WSL2 как версию по умолчанию
    try {
        wsl --set-default-version 2 2>$null | Out-Null
        Write-OK "WSL2 включён и настроен"
    } catch {
        Write-Warn "Не удалось установить WSL2 по умолчанию — продолжаем"
    }
}

# ─── Проверить наличие Docker ─────────────────────────────────────────────────
function Get-DockerStatus {
    try {
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $dockerVersion
        }
    } catch { }
    return $null
}

# ─── Установить Docker Desktop ────────────────────────────────────────────────
function Install-DockerDesktop {
    Write-Step "Установка Docker Desktop..."

    $dockerVersion = Get-DockerStatus
    if ($null -ne $dockerVersion) {
        Write-OK "Docker уже установлен: $dockerVersion"
        return
    }

    # Проверить наличие Chocolatey
    $chocoAvailable = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    if ($chocoAvailable) {
        Write-Info "Устанавливаем через Chocolatey..."
        choco install docker-desktop -y --no-progress
    } else {
        # Скачать установщик напрямую
        Write-Info "Скачиваем Docker Desktop..."
        $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
        $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($installerUrl, $installerPath)
        Write-OK "Скачан: $installerPath"

        Write-Info "Запускаем установщик Docker Desktop..."
        Write-Warn "Следуйте инструкциям установщика, затем перезапустите систему."
        Start-Process -FilePath $installerPath -ArgumentList "install --quiet" -Wait
    }

    Write-OK "Docker Desktop установлен"
    Write-Warn "Запустите Docker Desktop и дождитесь его полной загрузки."
    Write-Warn "Затем запустите этот скрипт снова."

    # Открыть Docker Desktop
    $dockerDesktopPath = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktopPath) {
        Start-Process $dockerDesktopPath
    }

    if (-not $Silent) {
        Write-Host ""
        Read-Host "Нажмите Enter после запуска Docker Desktop"
    }
}

# ─── Дождаться запуска Docker ─────────────────────────────────────────────────
function Wait-DockerReady {
    Write-Step "Ожидание запуска Docker..."
    $maxAttempts = 30
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $result = docker info 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Docker готов к работе"
                return
            }
        } catch { }
        Write-Info "Попытка $i/$maxAttempts — ожидаем запуска Docker..."
        Start-Sleep -Seconds 5
    }
    Write-Fail "Docker не запустился за $($maxAttempts * 5) секунд."
    Write-Fail "Убедитесь что Docker Desktop запущен и повторите."
    exit 1
}

# ─── Создать директорию и файлы ───────────────────────────────────────────────
function New-InstallDirectory {
    Write-Step "Создание директории установки: $InstallDir"

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Скопировать файлы если запускается из директории проекта.
    # $PSScriptRoot — надёжно работает как при ручном запуске, так и из NSIS.
    $scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $projectDir = Split-Path -Parent $scriptDir
    $composeFile = Join-Path $projectDir "docker-compose.yml"

    if (Test-Path $composeFile) {
        Write-Info "Копируем файлы проекта..."
        Copy-Item -Path "$projectDir\docker-compose.yml"     -Destination $InstallDir -Force
        Copy-Item -Path "$projectDir\docker-compose.gpu.yml" -Destination $InstallDir -Force -ErrorAction SilentlyContinue
        if (Test-Path "$projectDir\scripts") {
            Copy-Item -Path "$projectDir\scripts" -Destination $InstallDir -Recurse -Force
        }
        Write-OK "Файлы скопированы"
    } else {
        # Создать docker-compose.yml если его нет
        Write-Info "Создаём docker-compose.yml..."
        $composeContent = @"
services:
  ollama:
    image: ollama/ollama:latest
    container_name: super-sistema-ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_KEEP_ALIVE=24h
      - OLLAMA_NUM_PARALLEL=1
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  open-webui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: super-sistema-webui
    restart: unless-stopped
    ports:
      - "$($WebUIPort):8080"
    volumes:
      - open_webui_data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=`${WEBUI_SECRET_KEY:-super-sistema-secret}
      - WEBUI_AUTH=false
    depends_on:
      ollama:
        condition: service_healthy

volumes:
  ollama_data:
    name: super-sistema-ollama-data
  open_webui_data:
    name: super-sistema-webui-data

networks:
  default:
    name: super-sistema-network
"@
        $composeContent | Out-File -FilePath "$InstallDir\docker-compose.yml" -Encoding UTF8
        Write-OK "docker-compose.yml создан"
    }
}

# ─── Создать .env файл ────────────────────────────────────────────────────────
function New-EnvFile {
    $envFile = "$InstallDir\.env"

    if (Test-Path $envFile) {
        Write-OK ".env уже существует, пропускаем"
        return
    }

    Write-Step "Создание .env файла..."

    # Генерируем случайный ключ
    $secretKey = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

    $envContent = @"
# Super Sistema — Конфигурация
WEBUI_SECRET_KEY=$secretKey
WEBUI_PORT=$WebUIPort
WEBUI_AUTH=false
OLLAMA_KEEP_ALIVE=24h
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
DEFAULT_MODELS=llama3.2:3b
"@

    $envContent | Out-File -FilePath $envFile -Encoding UTF8
    Write-OK ".env создан: $envFile"
}

# ─── Запустить контейнеры ─────────────────────────────────────────────────────
function Start-Containers {
    Write-Step "Запуск Super Sistema..."

    Set-Location $InstallDir

    Write-Info "Скачиваем Docker образы (может занять 5-10 минут)..."
    docker compose pull 2>&1 | Where-Object { $_ -match "Pull|Pulled|Status" } | ForEach-Object { Write-Info $_ }

    Write-Info "Запускаем контейнеры..."
    docker compose up -d

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Ошибка при запуске контейнеров."
        exit 1
    }

    Write-OK "Контейнеры запущены"
}

# ─── Скачать стартовую модель ─────────────────────────────────────────────────
function Get-StarterModel {
    if ($NoModel) { return }

    Write-Step "Скачиваем стартовую модель AI..."
    Write-Info "llama3.2:3b (~2 GB) — это займёт несколько минут..."

    # Ожидаем запуска Ollama
    $maxAttempts = 30
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            docker exec super-sistema-ollama ollama list 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
        } catch { }
        if ($i -eq $maxAttempts) {
            Write-Warn "Ollama не запустился. Скачайте модель вручную:"
            Write-Warn "  docker exec super-sistema-ollama ollama pull llama3.2:3b"
            return
        }
        Start-Sleep -Seconds 3
    }

    docker exec super-sistema-ollama ollama pull llama3.2:3b
    Write-OK "Модель llama3.2:3b готова"
}

# ─── Создать ярлык на рабочем столе ──────────────────────────────────────────
function New-DesktopShortcut {
    Write-Step "Создание ярлыка на рабочем столе..."

    $shortcutPath = "$env:USERPROFILE\Desktop\Super Sistema.url"
    $shortcutContent = @"
[InternetShortcut]
URL=http://localhost:$WebUIPort
IconFile=$env:SystemRoot\System32\shell32.dll
IconIndex=14
"@
    $shortcutContent | Out-File -FilePath $shortcutPath -Encoding ASCII
    Write-OK "Ярлык создан на рабочем столе"
}

# ─── Финальное сообщение ─────────────────────────────────────────────────────
function Show-Success {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║       ✓  УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!               ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Откройте браузер:" -NoNewline
    Write-Host "  http://localhost:$WebUIPort" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Управление:" -ForegroundColor Yellow
    Write-Host "    Запуск:    cd `"$InstallDir`" && docker compose up -d"
    Write-Host "    Остановка: cd `"$InstallDir`" && docker compose down"
    Write-Host "    Логи:      cd `"$InstallDir`" && docker compose logs -f"
    Write-Host ""

    # Открыть браузер автоматически
    if (-not $Silent) {
        Start-Sleep -Seconds 5
        Start-Process "http://localhost:$WebUIPort"
    }
}

# ─── Главная функция ─────────────────────────────────────────────────────────
function Main {
    Write-Header

    if (-not (Test-Admin)) {
        Write-Fail "Требуются права администратора!"
        Write-Fail "Кликните правой кнопкой на setup.ps1 → 'Запустить с правами администратора'"
        if (-not $Silent) { Read-Host "Нажмите Enter для выхода" }
        exit 1
    }

    Test-WindowsVersion
    Enable-WSL2
    Install-DockerDesktop
    Wait-DockerReady
    New-InstallDirectory
    New-EnvFile
    Start-Containers
    Get-StarterModel
    New-DesktopShortcut
    Show-Success
}

Main
