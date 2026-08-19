#!/usr/bin/env bash
# Super Sistema v1.1 — Установщик для Linux
# Использование: git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
#                cd super-sistema && bash install.sh
# Поддерживает: Ubuntu 20.04+, Debian 11+, CentOS 8+, Fedora 36+, Arch Linux,
#               Manjaro, EndeavourOS, Garuda, ArcoLinux и другие Arch-based

set -euo pipefail

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Логирование ──────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── Заголовок ────────────────────────────────────────────────────────────────
print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          SUPER SISTEMA — Установка v1.0              ║"
    echo "║       Локальный AI-ассистент без облаков             ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─── Проверка прав ────────────────────────────────────────────────────────────
check_privileges() {
    if [[ "$EUID" -eq 0 ]]; then
        SUDO=""
    elif command -v sudo &>/dev/null; then
        SUDO="sudo"
        log_info "Используем sudo для установки"
    else
        log_error "Нет прав root и sudo недоступен. Запустите от root."
        exit 1
    fi
}

# ─── Определение дистрибутива ─────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-}"
    elif command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        DISTRO_VERSION=$(lsb_release -sr)
    else
        DISTRO="unknown"
        DISTRO_VERSION=""
    fi
    log_info "Дистрибутив: ${DISTRO} ${DISTRO_VERSION}"
}

# ─── Установка Docker ─────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_ok "Docker уже установлен: v${DOCKER_VERSION}"
        return 0
    fi

    log_step "Установка Docker..."

    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop)
            $SUDO apt-get update -qq
            $SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release

            $SUDO install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/"${DISTRO}"/gpg | \
                $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
            $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO} \
$(lsb_release -cs) stable" | \
                $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

            $SUDO apt-get update -qq
            $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;

        centos|rhel|rocky|almalinux)
            $SUDO yum install -y -q yum-utils
            $SUDO yum-config-manager --add-repo \
                https://download.docker.com/linux/centos/docker-ce.repo
            $SUDO yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;

        fedora)
            $SUDO dnf install -y -q dnf-plugins-core
            $SUDO dnf config-manager --add-repo \
                https://download.docker.com/linux/fedora/docker-ce.repo
            $SUDO dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;

        arch|manjaro|endeavouros|garuda|arcolinux)
            # docker пакет на Arch уже включает Compose v2 plugin (docker compose).
            # docker-compose — устаревший v1 (Python), устанавливать не нужно.
            $SUDO pacman -Sy --noconfirm docker
            # Если Compose v2 недоступен — установить отдельный пакет
            if ! docker compose version &>/dev/null 2>&1; then
                $SUDO pacman -S --noconfirm docker-compose 2>/dev/null || true
            fi
            ;;

        *)
            log_warn "Неизвестный дистрибутив. Пробуем универсальный установщик Docker..."
            curl -fsSL https://get.docker.com | $SUDO sh
            ;;
    esac

    # Запустить и включить Docker
    $SUDO systemctl enable docker --now
    log_ok "Docker установлен"
}

# ─── Добавить пользователя в группу docker ────────────────────────────────────
setup_docker_group() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi

    if ! groups "$USER" | grep -q docker; then
        log_info "Добавляем пользователя ${USER} в группу docker..."
        $SUDO usermod -aG docker "$USER"
        log_warn "Нужно перезайти в систему чтобы изменения вступили в силу."
        log_warn "Или выполните: newgrp docker"
        # Перезапустить скрипт в контексте группы docker для текущей сессии.
        # Флаг --skip-group предотвращает бесконечную рекурсию.
        exec sg docker "bash $(realpath "$0") --skip-group"
    fi
}

# ─── Проверка Docker Compose ──────────────────────────────────────────────────
check_docker_compose() {
    if docker compose version &>/dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "v2")
        log_ok "Docker Compose v2 доступен: ${COMPOSE_VERSION}"
        return 0
    fi

    if command -v docker-compose &>/dev/null; then
        COMPOSE_VER=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log_warn "Найден docker-compose v1 (${COMPOSE_VER}). Рекомендуется v2."
        return 0
    fi

    log_error "Docker Compose не найден. Установите docker-compose-plugin."
    exit 1
}

# ─── Определить директорию установки ─────────────────────────────────────────
get_install_dir() {
    if [[ "$EUID" -eq 0 ]]; then
        INSTALL_DIR="/opt/super-sistema"
    else
        INSTALL_DIR="${HOME}/super-sistema"
    fi

    # Если скрипт запущен из директории проекта — использовать её
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
        INSTALL_DIR="${SCRIPT_DIR}"
        log_info "Используем текущую директорию: ${INSTALL_DIR}"
    else
        log_info "Директория установки: ${INSTALL_DIR}"
        mkdir -p "${INSTALL_DIR}"
    fi
}

# ─── Создать .env файл ────────────────────────────────────────────────────────
create_env_file() {
    local env_file="${INSTALL_DIR}/.env"

    if [[ -f "${env_file}" ]]; then
        log_ok ".env файл уже существует, пропускаем"
        return 0
    fi

    log_step "Создаём файл конфигурации .env..."

    # Генерируем случайный секретный ключ
    local secret_key
    if command -v openssl &>/dev/null; then
        secret_key=$(openssl rand -hex 32)
    else
        secret_key=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 64 | head -n 1)
    fi

    cat > "${env_file}" << EOF
# Super Sistema — Конфигурация
# Создано автоматически при установке: $(date)

WEBUI_SECRET_KEY=${secret_key}
WEBUI_PORT=3000
WEBUI_AUTH=false

OLLAMA_KEEP_ALIVE=24h
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1

DEFAULT_MODELS=llama3.2:3b
EOF

    log_ok "Файл .env создан: ${env_file}"
}

# ─── Запуск контейнеров ───────────────────────────────────────────────────────
start_containers() {
    log_step "Запуск Super Sistema..."

    cd "${INSTALL_DIR}"

    # Команда compose как массив — надёжно работает и с "docker compose" и с "docker-compose"
    local -a DC
    if docker compose version &>/dev/null 2>&1; then
        DC=(docker compose)
        log_info "Используем Docker Compose v2"
    else
        DC=(docker-compose)
        log_info "Используем docker-compose v1"
    fi

    # Остановить если уже запущено
    "${DC[@]}" down --remove-orphans 2>/dev/null || true

    # Скачать образы и запустить
    log_info "Скачиваем Docker образы (может занять несколько минут)..."
    "${DC[@]}" pull

    log_info "Запускаем контейнеры..."
    "${DC[@]}" up -d

    log_ok "Контейнеры запущены"
}

# ─── Скачать стартовую модель ─────────────────────────────────────────────────
download_starter_model() {
    log_step "Скачиваем стартовую AI модель..."
    log_info "Скачиваем llama3.2:3b (2 GB) — это займёт несколько минут..."
    log_info "Прогресс:"

    # Ждём пока Ollama запустится
    local retries=0
    while ! docker exec super-sistema-ollama ollama list &>/dev/null; do
        retries=$((retries + 1))
        if [[ $retries -gt 30 ]]; then
            log_warn "Ollama не запустился за 60 секунд. Скачайте модель вручную:"
            log_warn "  docker exec super-sistema-ollama ollama pull llama3.2:3b"
            return 1
        fi
        sleep 2
    done

    docker exec super-sistema-ollama ollama pull llama3.2:3b
    log_ok "Модель llama3.2:3b успешно скачана"
}

# ─── Дождаться запуска веб-интерфейса ────────────────────────────────────────
wait_for_webui() {
    log_info "Ожидаем запуска веб-интерфейса..."
    local port
    port=$(grep -E "^WEBUI_PORT=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "3000")
    local url="http://localhost:${port}"

    # Open WebUI при первом запуске инициализирует БД и качает зависимости — нужно до 5 минут
    local retries=0
    local max_retries=90   # 90 × 4 сек = 6 минут
    while ! curl -sf "${url}/health" &>/dev/null; do
        retries=$((retries + 1))
        if [[ $retries -gt $max_retries ]]; then
            log_warn "Веб-интерфейс не ответил за $((max_retries * 4)) секунд."
            log_warn "Контейнер может ещё запускаться. Проверьте:"
            log_warn "  docker compose logs open-webui --tail=30"
            log_warn "  docker compose ps"
            log_warn "Как только запустится — откройте: ${url}"
            return 1
        fi
        # Показывать прогресс каждые 20 секунд
        if (( retries % 5 == 0 )); then
            log_info "Ожидаем Open WebUI... (${retries}/${max_retries})"
        fi
        sleep 4
    done

    log_ok "Веб-интерфейс доступен: ${url}"
}

# ─── Финальное сообщение ──────────────────────────────────────────────────────
print_success() {
    local port
    port=$(grep -E "^WEBUI_PORT=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "3000")

    echo -e "\n${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        ✓  УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!              ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Откройте браузер:${NC}  ${CYAN}http://localhost:${port}${NC}"
    echo ""
    echo -e "  ${BOLD}Команды управления:${NC}"
    echo -e "    Запуск:       ${YELLOW}cd ${INSTALL_DIR} && docker compose up -d${NC}"
    echo -e "    Остановка:    ${YELLOW}cd ${INSTALL_DIR} && docker compose down${NC}"
    echo -e "    Логи:         ${YELLOW}cd ${INSTALL_DIR} && docker compose logs -f${NC}"
    echo -e "    Модели:       ${YELLOW}bash ${INSTALL_DIR}/scripts/download-models.sh${NC}"
    echo ""
    echo -e "  ${BOLD}Скачать ещё модели:${NC}"
    echo -e "    ${YELLOW}bash scripts/download-models.sh${NC}"
    echo ""
}

# ─── Главная функция ──────────────────────────────────────────────────────────
main() {
    # --skip-group: пропустить настройку группы docker при перезапуске через sg
    local skip_group=false
    for arg in "$@"; do
        [[ "$arg" == "--skip-group" ]] && skip_group=true
    done

    print_header
    check_privileges
    detect_distro
    install_docker
    [[ "$skip_group" == "false" ]] && setup_docker_group
    check_docker_compose
    get_install_dir
    create_env_file
    start_containers
    download_starter_model
    wait_for_webui
    print_success
}

main "$@"
