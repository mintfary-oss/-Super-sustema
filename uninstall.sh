#!/usr/bin/env bash
# Super Sistema — Удаление
# Использование: bash uninstall.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          SUPER SISTEMA — Удаление                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}${BOLD}ВНИМАНИЕ!${NC} Это удалит:"
echo "  • Docker контейнеры (open-webui, ollama)"
echo "  • Docker сеть (super-sistema-network)"
echo ""
echo -e "${RED}ДАННЫЕ БУДУТ СОХРАНЕНЫ если не выбрать полное удаление.${NC}"
echo ""
read -rp "Продолжить? (y/N): " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Отменено."
    exit 0
fi

echo ""
read -rp "Удалить также ВСЕ ДАННЫЕ (модели, история чатов)? (y/N): " delete_data

# Определить команду compose
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# Найти директорию
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
    cd "${SCRIPT_DIR}"
else
    echo -e "${RED}docker-compose.yml не найден в текущей директории${NC}"
    exit 1
fi

echo -e "\n${CYAN}Останавливаем контейнеры...${NC}"
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

if [[ "${delete_data,,}" == "y" ]]; then
    echo -e "${RED}Удаляем тома с данными...${NC}"
    docker volume rm super-sistema-ollama-data super-sistema-webui-data 2>/dev/null || true
    echo -e "${GREEN}Данные удалены.${NC}"
else
    echo -e "${GREEN}Данные сохранены в Docker volumes.${NC}"
    echo "  Просмотр: docker volume ls | grep super-sistema"
    echo "  Удалить позже: docker volume rm super-sistema-ollama-data super-sistema-webui-data"
fi

echo -e "\n${GREEN}${BOLD}Super Sistema удалён.${NC}"
