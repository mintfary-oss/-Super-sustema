#!/usr/bin/env bash
# Super Sistema — Установка GPU Monitor как systemd сервиса
# Использование: sudo bash scripts/install-gpu-monitor.sh
#
# После установки:
#   systemctl status super-sistema-gpu   — статус
#   systemctl start  super-sistema-gpu   — запустить
#   systemctl stop   super-sistema-gpu   — остановить
#   journalctl -u super-sistema-gpu -f   — логи

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ "$EUID" -ne 0 ]]; then
    echo "Запустите с правами root: sudo bash scripts/install-gpu-monitor.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SCRIPT="${SCRIPT_DIR}/watch-gpu.sh"
SERVICE_NAME="super-sistema-gpu"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo -e "${CYAN}${BOLD}Установка GPU Monitor как systemd сервиса...${NC}"

# Проверить наличие watch-gpu.sh
if [[ ! -f "${WATCH_SCRIPT}" ]]; then
    echo "ОШИБКА: ${WATCH_SCRIPT} не найден"
    exit 1
fi
chmod +x "${WATCH_SCRIPT}"

# Создать systemd unit файл
cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Super Sistema GPU Hot-Plug Monitor (Tesla P100)
After=docker.service network-online.target
Wants=docker.service
Documentation=https://github.com/mintfary-oss/-Super-sustema

[Service]
Type=simple
ExecStart=/bin/bash ${WATCH_SCRIPT}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=super-sistema-gpu

# Логирование
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓${NC} Сервис создан: ${SERVICE_FILE}"

# Перезагрузить systemd и включить сервис
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start  "${SERVICE_NAME}"

sleep 2

echo ""
STATUS=$(systemctl is-active "${SERVICE_NAME}" 2>/dev/null || echo "unknown")
if [[ "$STATUS" == "active" ]]; then
    echo -e "${GREEN}${BOLD}✓ Сервис запущен!${NC}"
else
    echo -e "${YELLOW}⚠ Статус: ${STATUS}${NC}"
fi

echo ""
echo "Команды управления:"
echo -e "  ${YELLOW}systemctl status ${SERVICE_NAME}${NC}       — статус"
echo -e "  ${YELLOW}systemctl stop   ${SERVICE_NAME}${NC}       — остановить"
echo -e "  ${YELLOW}journalctl -u ${SERVICE_NAME} -f${NC}       — логи"
echo ""
echo "Лог файл: /var/log/super-sistema-gpu.log"
echo ""
echo -e "${CYAN}Теперь при подключении Tesla P100 к работающему ПК${NC}"
echo "сервис автоматически обнаружит карту и запустит настройку!"
