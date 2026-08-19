#!/usr/bin/env bash
# Super Sistema — Установка и активация Tesla P100
# Использование: sudo bash scripts/setup-tesla-p100.sh
#
# Что делает скрипт:
#  1. Проверяет наличие Tesla P100 в системе (lspci)
#  2. Устанавливает NVIDIA драйвер если отсутствует
#  3. Устанавливает CUDA Toolkit
#  4. Устанавливает nvidia-container-toolkit (для Docker)
#  5. Настраивает Docker runtime
#  6. Перезапускает Super Sistema с поддержкой GPU
#  7. Проверяет что Ollama видит Tesla P100
#
# ВАЖНО — проблема с монитором:
#  Tesla P100 не имеет видеовыходов (это вычислительная карта).
#  Если монитор гаснет при включении P100 — в BIOS установите:
#    "Primary Display" → "IGFX" (или "Integrated" / "CPU Graphics")
#  Это позволит видеосигналу всегда идти через процессор,
#  а Tesla будет использоваться только для вычислений (AI).

set -euo pipefail

# ─── Цвета ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_step()  { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }
log_ok()    { echo -e "  ${GREEN}[OK]${NC}    $*"; }
log_info()  { echo -e "  ${BLUE}[INFO]${NC}  $*"; }
log_warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "  ${RED}[ERROR]${NC} $*"; }

# ─── Шапка ─────────────────────────────────────────────────────────────────
print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     SUPER SISTEMA — Tesla P100 Setup v1.0           ║"
    echo "║     Активация GPU для нейросетей и Ollama           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─── Проверка root ──────────────────────────────────────────────────────────
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "Запустите с правами root: sudo bash scripts/setup-tesla-p100.sh"
        exit 1
    fi
}

# ─── Определение дистрибутива ───────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-}"
        DISTRO_CODENAME="${VERSION_CODENAME:-}"
    else
        DISTRO="unknown"; DISTRO_VERSION=""; DISTRO_CODENAME=""
    fi
    log_info "Дистрибутив: ${DISTRO} ${DISTRO_VERSION}"
}

# ─── Поиск Tesla P100 ───────────────────────────────────────────────────────
detect_tesla_p100() {
    log_step "Поиск Tesla P100 в системе..."

    if ! command -v lspci &>/dev/null; then
        apt-get install -y -qq pciutils 2>/dev/null || \
        yum install -y -q pciutils 2>/dev/null || true
    fi

    # Поиск любого NVIDIA устройства
    NVIDIA_DEVICES=$(lspci | grep -i "NVIDIA" || true)
    P100_FOUND=$(lspci | grep -i "Tesla P100\|GF100\|GP100" || true)

    if [[ -z "$NVIDIA_DEVICES" ]]; then
        echo ""
        log_warn "NVIDIA карта не обнаружена в lspci."
        echo ""
        echo -e "  ${YELLOW}Возможные причины:${NC}"
        echo "  1. Tesla P100 не подключена к материнской плате"
        echo "  2. BIOS не инициализировал карту"
        echo "  3. Карта не получает питание"
        echo ""
        echo -e "  ${BOLD}Решение проблемы с монитором при горячем подключении:${NC}"
        echo "  ╔════════════════════════════════════════════════════╗"
        echo "  ║ BIOS → Advanced → Primary Display → IGFX          ║"
        echo "  ║    или  Integrated Graphics / CPU Graphics         ║"
        echo "  ╚════════════════════════════════════════════════════╝"
        echo "  После этого изменения:"
        echo "  • Монитор всегда будет работать через процессор"
        echo "  • Tesla P100 будет только для вычислений (AI/Ollama)"
        echo "  • Подключите P100 и перезагрузите компьютер"
        echo ""
        read -rp "Хотите продолжить установку драйверов? (y/N): " cont
        [[ "${cont,,}" != "y" ]] && exit 0
    else
        log_ok "NVIDIA устройства найдены:"
        echo "$NVIDIA_DEVICES" | while read -r line; do
            echo "    $line"
        done
        if [[ -n "$P100_FOUND" ]]; then
            log_ok "${BOLD}Tesla P100 обнаружена!${NC}"
        else
            log_info "Tesla P100 не определена по имени, но NVIDIA карта присутствует."
            log_info "Продолжаем установку..."
        fi
    fi
}

# ─── Проверка текущего драйвера ─────────────────────────────────────────────
check_existing_driver() {
    log_step "Проверка NVIDIA драйвера..."

    if command -v nvidia-smi &>/dev/null; then
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
        log_ok "Драйвер уже установлен: v${DRIVER_VERSION}"
        log_ok "GPU: ${GPU_NAME}"
        DRIVER_INSTALLED=true
    else
        log_info "NVIDIA драйвер не установлен — устанавливаем..."
        DRIVER_INSTALLED=false
    fi
}

# ─── Установка NVIDIA драйвера ──────────────────────────────────────────────
install_nvidia_driver() {
    if [[ "$DRIVER_INSTALLED" == "true" ]]; then
        return 0
    fi

    log_step "Установка NVIDIA драйвера (рекомендован 525+ для Tesla P100)..."

    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop)
            # Добавить репозиторий NVIDIA
            apt-get install -y -qq software-properties-common

            # Проверить возможность автоустановки через ubuntu-drivers
            if command -v ubuntu-drivers &>/dev/null; then
                log_info "Определяем рекомендуемый драйвер..."
                ubuntu-drivers devices 2>/dev/null | grep -E "recommended|nvidia" | head -5 || true
                log_info "Устанавливаем рекомендуемый драйвер..."
                ubuntu-drivers autoinstall 2>/dev/null || {
                    log_info "Устанавливаем nvidia-driver-525 напрямую..."
                    apt-get install -y nvidia-driver-525
                }
            else
                # Добавить PPA для новых версий
                add-apt-repository -y ppa:graphics-drivers/ppa 2>/dev/null || true
                apt-get update -qq
                # Tesla P100 (GP100) — минимальный драйвер 396, рекомендован 525+
                apt-get install -y nvidia-driver-525 2>/dev/null || \
                apt-get install -y nvidia-driver-520 2>/dev/null || \
                apt-get install -y nvidia-driver-515 2>/dev/null || {
                    log_error "Не удалось установить драйвер автоматически."
                    echo "Установите вручную: sudo apt install nvidia-driver-525"
                    exit 1
                }
            fi
            ;;

        centos|rhel|rocky|almalinux)
            # Установить EPEL и DKMS
            yum install -y epel-release kernel-devel kernel-headers dkms
            # Загрузить и установить драйвер NVIDIA
            ARCH=$(uname -m)
            DRIVER_URL="https://us.download.nvidia.com/tesla/525.105.17/NVIDIA-Linux-${ARCH}-525.105.17.run"
            log_info "Скачиваем NVIDIA драйвер..."
            curl -fsSL "$DRIVER_URL" -o /tmp/nvidia-driver.run
            chmod +x /tmp/nvidia-driver.run
            /tmp/nvidia-driver.run --silent --no-opengl-files --no-x-check
            ;;

        fedora)
            dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
            ;;

        arch|manjaro)
            pacman -Sy --noconfirm nvidia nvidia-utils
            ;;

        *)
            log_warn "Неизвестный дистрибутив. Пробуем universal installer..."
            ARCH=$(uname -m)
            DRIVER_URL="https://us.download.nvidia.com/tesla/525.105.17/NVIDIA-Linux-${ARCH}-525.105.17.run"
            curl -fsSL "$DRIVER_URL" -o /tmp/nvidia-driver.run
            chmod +x /tmp/nvidia-driver.run
            /tmp/nvidia-driver.run --silent --no-opengl-files --no-x-check
            ;;
    esac

    log_ok "NVIDIA драйвер установлен"
    log_warn "После завершения скрипта потребуется ПЕРЕЗАГРУЗКА."
    NEED_REBOOT=true
}

# ─── Установка nvidia-container-toolkit ────────────────────────────────────
install_container_toolkit() {
    log_step "Установка nvidia-container-toolkit (для Docker)..."

    if dpkg -l nvidia-container-toolkit &>/dev/null 2>&1 || \
       rpm -q nvidia-container-toolkit &>/dev/null 2>&1; then
        log_ok "nvidia-container-toolkit уже установлен"
        return 0
    fi

    # Официальный способ от NVIDIA для всех дистрибутивов
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    DIST=$(. /etc/os-release; echo "$ID$VERSION_ID" | tr -d '.')

    # Добавить GPG ключ репозитория NVIDIA
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null

    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop)
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq nvidia-container-toolkit
            ;;

        centos|rhel|rocky|almalinux|fedora)
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
            yum install -y nvidia-container-toolkit 2>/dev/null || \
            dnf install -y nvidia-container-toolkit
            ;;

        arch|manjaro)
            # AUR
            if command -v yay &>/dev/null; then
                sudo -u "${SUDO_USER:-$USER}" yay -Sy --noconfirm nvidia-container-toolkit
            else
                log_warn "Установите nvidia-container-toolkit из AUR вручную"
            fi
            ;;
    esac

    log_ok "nvidia-container-toolkit установлен"
}

# ─── Настройка Docker runtime ────────────────────────────────────────────────
configure_docker_runtime() {
    log_step "Настройка Docker для работы с NVIDIA GPU..."

    if ! command -v docker &>/dev/null; then
        log_warn "Docker не найден. Установите Docker и запустите скрипт снова."
        return 1
    fi

    # Настроить NVIDIA как default runtime
    nvidia-ctk runtime configure --runtime=docker 2>/dev/null || {
        log_warn "nvidia-ctk не найден, настраиваем вручную..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "runc"
}
EOF
    }

    # Перезапустить Docker
    systemctl daemon-reload
    systemctl restart docker
    sleep 3

    log_ok "Docker runtime настроен"
}

# ─── Тест GPU в Docker ───────────────────────────────────────────────────────
test_gpu_docker() {
    log_step "Тестирование GPU в Docker..."

    # Быстрый тест
    if docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi 2>/dev/null; then
        log_ok "GPU доступен в Docker!"
    else
        log_warn "nvidia-smi в Docker не запустился."
        log_info "Это нормально если драйвер только что установлен — нужна перезагрузка."
    fi
}

# ─── Определить директорию Super Sistema ────────────────────────────────────
find_project_dir() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    if [[ ! -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
        # Попробовать стандартные места
        for dir in /opt/super-sistema "${HOME}/super-sistema"; do
            if [[ -f "${dir}/docker-compose.yml" ]]; then
                PROJECT_DIR="$dir"
                break
            fi
        done
    fi
    log_info "Директория проекта: ${PROJECT_DIR}"
}

# ─── Перезапустить Ollama с GPU ──────────────────────────────────────────────
restart_ollama_with_gpu() {
    log_step "Перезапуск Super Sistema с поддержкой Tesla P100..."

    if [[ ! -f "${PROJECT_DIR}/docker-compose.gpu.yml" ]]; then
        log_warn "docker-compose.gpu.yml не найден в ${PROJECT_DIR}"
        return 1
    fi

    cd "${PROJECT_DIR}"

    # Определить команду compose
    if docker compose version &>/dev/null; then
        COMPOSE="docker compose"
    else
        COMPOSE="docker-compose"
    fi

    # Остановить текущие контейнеры
    log_info "Останавливаем текущие контейнеры..."
    $COMPOSE down 2>/dev/null || true

    # Запустить с GPU
    log_info "Запускаем с Tesla P100..."
    $COMPOSE -f docker-compose.gpu.yml up -d

    log_ok "Super Sistema запущен с GPU профилем"
}

# ─── Проверить что Ollama видит GPU ─────────────────────────────────────────
verify_ollama_gpu() {
    log_step "Проверка что Ollama видит Tesla P100..."

    # Ждём запуска Ollama
    local retries=0
    while ! docker exec super-sistema-ollama ollama list &>/dev/null; do
        retries=$((retries + 1))
        [[ $retries -gt 20 ]] && { log_warn "Ollama не запустился за 60 сек"; return 1; }
        sleep 3
    done

    # Проверка через nvidia-smi внутри контейнера
    if docker exec super-sistema-ollama nvidia-smi 2>/dev/null; then
        log_ok "Tesla P100 видна внутри контейнера Ollama!"
    else
        log_warn "nvidia-smi не ответил внутри контейнера."
        log_info "Если драйвер только что установлен — перезагрузите систему."
    fi

    # Проверка через Ollama API
    sleep 5
    OLLAMA_INFO=$(curl -s http://localhost:11434/api/tags 2>/dev/null || echo "{}")
    log_ok "Ollama API отвечает"
}

# ─── Создать статус-файл ─────────────────────────────────────────────────────
write_gpu_status() {
    log_step "Сохраняем статус GPU..."

    STATUS_FILE="${PROJECT_DIR}/.gpu-status"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "NVIDIA (драйвер ещё не загружен)")
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 || echo "N/A")
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "установлен, нужна перезагрузка")

    cat > "${STATUS_FILE}" << EOF
GPU=${GPU_NAME}
MEMORY=${GPU_MEMORY}
DRIVER=${DRIVER_VER}
SETUP_DATE=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=active
EOF

    log_ok "Статус сохранён: ${STATUS_FILE}"
}

# ─── Итоговый отчёт ──────────────────────────────────────────────────────────
print_result() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         Tesla P100 — Настройка завершена            ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${BOLD}Статус GPU:${NC}"
    nvidia-smi --query-gpu=name,memory.total,driver_version,temperature.gpu \
        --format=csv,noheader 2>/dev/null | \
        awk -F',' '{printf "    GPU:        %s\n    VRAM:       %s\n    Драйвер:    %s\n    Температура:%s\n", $1,$2,$3,$4}' \
        || echo "    (будет доступно после перезагрузки)"

    echo ""
    echo -e "  ${BOLD}Веб-интерфейс:${NC}       ${CYAN}http://localhost:3000${NC}  (Ollama + OpenWebUI)"
    echo -e "  ${BOLD}GPU Панель:${NC}          ${CYAN}http://localhost:8765${NC}  (статус Tesla P100)"
    echo ""

    if [[ "${NEED_REBOOT:-false}" == "true" ]]; then
        echo -e "  ${RED}${BOLD}⚠  ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА${NC}"
        echo "  После перезагрузки Tesla P100 будет полностью активна."
        echo "  Затем запустите:"
        echo -e "    ${YELLOW}cd ${PROJECT_DIR} && docker compose -f docker-compose.gpu.yml up -d${NC}"
        echo ""
        read -rp "  Перезагрузить сейчас? (y/N): " reboot_now
        if [[ "${reboot_now,,}" == "y" ]]; then
            echo "  Перезагрузка через 5 секунд..."
            sleep 5
            reboot
        fi
    else
        echo -e "  ${GREEN}Tesla P100 готова к работе!${NC}"
        echo "  Ollama будет использовать GPU для всех запросов."
    fi
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
NEED_REBOOT=false
DRIVER_INSTALLED=false

main() {
    print_header
    check_root
    detect_distro
    detect_tesla_p100
    check_existing_driver
    install_nvidia_driver
    install_container_toolkit
    configure_docker_runtime
    test_gpu_docker
    find_project_dir
    restart_ollama_with_gpu
    verify_ollama_gpu
    write_gpu_status
    print_result
}

main "$@"
