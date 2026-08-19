#!/usr/bin/env bash
# Super Sistema — Мониторинг горячего подключения Tesla P100
# Запуск вручную:  sudo bash scripts/watch-gpu.sh
# Установка как сервис: sudo bash scripts/install-gpu-monitor.sh
#
# Что делает:
#  • Каждые 5 сек проверяет появление новой NVIDIA карты (lspci)
#  • При обнаружении — автоматически запускает setup-tesla-p100.sh
#  • Отслеживает файл-триггер от GPU Panel (кнопка в браузере)
#  • Пишет лог в /var/log/super-sistema-gpu.log

set -euo pipefail

# ─── Настройки ──────────────────────────────────────────────────────────────
POLL_INTERVAL=5                         # секунд между проверками
LOG_FILE="/var/log/super-sistema-gpu.log"
TRIGGER_FILE="/tmp/super-sistema/shared/gpu-setup-trigger"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup-tesla-p100.sh"
LOCK_FILE="/tmp/super-sistema-gpu-setup.lock"
STATUS_FILE="${PROJECT_DIR}/.gpu-status"

# ─── Цвета ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─── Логирование ─────────────────────────────────────────────────────────────
mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || LOG_FILE="/tmp/super-sistema-gpu.log"
mkdir -p /tmp/super-sistema/shared 2>/dev/null || true

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "${LOG_FILE}"
}

log_color() {
    local color="$1"; shift
    echo -e "${color}[$(date '+%H:%M:%S')]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

# ─── Получить список NVIDIA устройств ────────────────────────────────────────
get_nvidia_devices() {
    lspci 2>/dev/null | grep -i "nvidia\|tesla" | sort || true
}

# ─── Проверить что NVIDIA в рабочем состоянии ────────────────────────────────
nvidia_is_ready() {
    nvidia-smi &>/dev/null
}

# ─── Запустить установку (с защитой от двойного запуска) ────────────────────
run_setup() {
    local reason="$1"

    # Проверить lock — не запускать если уже идёт установка
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_age=$(( $(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo 0) ))
        if [[ $lock_age -lt 300 ]]; then
            log "Установка уже выполняется (lock файл, возраст: ${lock_age}с). Пропускаем."
            return 0
        else
            log "Старый lock файл (${lock_age}с). Удаляем."
            rm -f "${LOCK_FILE}"
        fi
    fi

    log_color "${GREEN}" "★ ОБНАРУЖЕНО: ${reason} → Запускаем setup-tesla-p100.sh"

    touch "${LOCK_FILE}"

    if [[ -x "${SETUP_SCRIPT}" ]]; then
        bash "${SETUP_SCRIPT}" >> "${LOG_FILE}" 2>&1
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log_color "${GREEN}" "✓ Установка завершена успешно"
        else
            log "⚠ Установка завершилась с кодом ${exit_code}"
        fi
    else
        log "ОШИБКА: Скрипт ${SETUP_SCRIPT} не найден или не исполняемый"
    fi

    rm -f "${LOCK_FILE}"
}

# ─── Удалить trigger файл ────────────────────────────────────────────────────
clear_trigger() {
    rm -f "${TRIGGER_FILE}" 2>/dev/null || true
}

# ─── Обработка сигналов ──────────────────────────────────────────────────────
cleanup() {
    log "watch-gpu.sh остановлен (PID $$)"
    rm -f "${LOCK_FILE}"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGQUIT

# ─── Шапка ───────────────────────────────────────────────────────────────────
print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     SUPER SISTEMA — GPU Hot-Plug Monitor            ║"
    echo "║     Мониторинг Tesla P100                           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Лог:    ${LOG_FILE}"
    echo "Триггер: ${TRIGGER_FILE}"
    echo "Проверка каждые: ${POLL_INTERVAL} сек"
    echo ""
    echo "Остановить: Ctrl+C  или  systemctl stop super-sistema-gpu"
    echo ""
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
main() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Запустите с правами root: sudo bash scripts/watch-gpu.sh"
        exit 1
    fi

    print_header
    log "watch-gpu.sh запущен (PID $$)"

    # Запомнить начальное состояние GPU
    PREV_DEVICES=$(get_nvidia_devices)

    if [[ -n "$PREV_DEVICES" ]]; then
        log_color "${GREEN}" "При старте обнаружены NVIDIA устройства:"
        echo "$PREV_DEVICES" | while read -r line; do log "  $line"; done

        # Если GPU есть, но драйвер не работает — настроить
        if ! nvidia_is_ready; then
            log_color "${YELLOW}" "GPU есть, но nvidia-smi не отвечает → запускаем настройку"
            run_setup "GPU присутствует, драйвер не настроен"
        else
            log_color "${GREEN}" "GPU и драйвер в норме. Мониторим дальше..."
        fi
    else
        log "При старте NVIDIA устройства не обнаружены. Ждём подключения..."
    fi

    # Основной цикл
    while true; do
        sleep "${POLL_INTERVAL}"

        # ── Проверка 1: Файл-триггер от веб-панели ──────────────────────────
        if [[ -f "${TRIGGER_FILE}" ]]; then
            # Примечание: local нельзя использовать вне функции, используем обычную переменную
            trigger_time=$(cat "${TRIGGER_FILE}" 2>/dev/null || echo "unknown")
            log_color "${CYAN}" "Триггер от GPU Panel (${trigger_time})"
            clear_trigger
            run_setup "Кнопка в браузере (GPU Panel)"
            unset trigger_time
            continue
        fi

        # ── Проверка 2: Новое NVIDIA устройство в PCIe ──────────────────────
        CURR_DEVICES=$(get_nvidia_devices)
        if [[ "$CURR_DEVICES" != "$PREV_DEVICES" ]]; then
            if [[ -z "$PREV_DEVICES" && -n "$CURR_DEVICES" ]]; then
                log_color "${GREEN}" "НОВАЯ КАРТА ОБНАРУЖЕНА!"
                echo "$CURR_DEVICES" | while read -r line; do log "  + ${line}"; done
                run_setup "Новая NVIDIA карта в PCIe"
            elif [[ -n "$PREV_DEVICES" && -z "$CURR_DEVICES" ]]; then
                log "GPU отключена (устройство исчезло из PCIe)"
                echo "STATUS=disconnected" > "${STATUS_FILE}"
                # Переключить на CPU-вариант
                local -a _dc
                if docker compose version &>/dev/null 2>&1; then _dc=(docker compose)
                else _dc=(docker-compose); fi
                cd "${PROJECT_DIR}" && "${_dc[@]}" up -d >>"${LOG_FILE}" 2>&1 &
            fi
            PREV_DEVICES="$CURR_DEVICES"
        fi

        # ── Проверка 3: GPU есть, но контейнер не запущен с GPU ─────────────
        if [[ -n "${CURR_DEVICES:-}" ]] && nvidia_is_ready; then
            # Проверить используется ли GPU вариант docker-compose
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "super-sistema-gpu-panel"; then
                log_color "${YELLOW}" "GPU активна, но GPU Panel не запущена → запускаем GPU конфиг"
                run_setup "GPU активна, контейнеры в CPU режиме"
            fi
        fi

    done
}

main "$@"
