#!/usr/bin/env bash
# Super Sistema — Обновление
# Использование: bash scripts/update.sh

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${CYAN}${BOLD}Super Sistema — Обновление...${NC}\n"

cd "${SCRIPT_DIR}"

# Определить команду compose
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo -e "${BLUE}[1/3]${NC} Скачиваем новые версии образов..."
$COMPOSE_CMD pull

echo -e "${BLUE}[2/3]${NC} Перезапускаем контейнеры..."
$COMPOSE_CMD up -d --remove-orphans

echo -e "${BLUE}[3/3]${NC} Очищаем старые образы..."
docker image prune -f 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}Обновление завершено!${NC}"
echo "Откройте http://localhost:3000"
