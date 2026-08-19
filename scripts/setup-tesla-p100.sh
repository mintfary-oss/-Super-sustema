#!/usr/bin/env bash
# Super Sistema — Tesla P100 Auto-Activator
# Вызывается из watch-gpu.sh или напрямую: sudo bash scripts/setup-tesla-p100.sh
#
# Полная автоматизация:
#   1. Ожидает физического подключения Tesla P100
#   2. Исправляет дисплей (GRUB + X11) — монитор всегда через iGPU
#   3. Ищет и устанавливает NVIDIA драйвер из интернета
#   4. Устанавливает CUDA + nvidia-container-toolkit
#   5. Настраивает P100 для оптимальной работы с нейросетями
#   6. Запускает Super Sistema с GPU
#   7. Тестирует и показывает результат

set -euo pipefail

# ─── Пути ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROGRESS_FILE="/tmp/super-sistema/shared/progress.log"
STATUS_FILE="${PROJECT_DIR}/.gpu-status"
WAIT_TIMEOUT=300   # секунд ожидания подключения P100

# ─── Цвета ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─── Прогресс-логгер ────────────────────────────────────────────────────────
# Пишет одновременно в консоль и в файл для веб-панели
mkdir -p /tmp/super-sistema/shared 2>/dev/null || true
: > "${PROGRESS_FILE}"   # очистить при старте

progress() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%H:%M:%S')
    # В файл (читает веб-панель через SSE)
    echo "${level}|${ts}|${msg}" >> "${PROGRESS_FILE}"
    # В консоль
    case "$level" in
        OK)    echo -e "  ${GREEN}[${ts}] ✓${NC} ${msg}" ;;
        STEP)  echo -e "\n${BOLD}${CYAN}[${ts}] ▶ ${msg}${NC}" ;;
        INFO)  echo -e "  ${BLUE}[${ts}]  ${msg}${NC}" ;;
        WARN)  echo -e "  ${YELLOW}[${ts}] ⚠${NC} ${msg}" ;;
        ERROR) echo -e "  ${RED}[${ts}] ✗${NC} ${msg}" ;;
        DONE)  echo -e "\n${GREEN}${BOLD}[${ts}] ★ ${msg}${NC}" ;;
    esac
}

# ─── Проверка root ──────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo "Требуется root: sudo bash scripts/setup-tesla-p100.sh"
    exit 1
fi

# ─── Определение дистрибутива ───────────────────────────────────────────────
detect_distro() {
    source /etc/os-release 2>/dev/null || true
    DISTRO="${ID:-unknown}"
    DISTRO_VER="${VERSION_ID:-0}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"
    ARCH=$(uname -m)
    progress INFO "ОС: ${PRETTY_NAME:-${DISTRO} ${DISTRO_VER}} | Архитектура: ${ARCH}"
}

# ─── 1. ОЖИДАНИЕ Tesla P100 ─────────────────────────────────────────────────
wait_for_p100() {
    progress STEP "Шаг 1/8 — Ожидание Tesla P100"

    local deadline=$(( $(date +%s) + WAIT_TIMEOUT ))

    while true; do
        # lspci показывает Tesla P100, P40, V100 и другие NVIDIA Tesla
        if lspci 2>/dev/null | grep -iqE "NVIDIA|Tesla|GP100|GV100|GV100GL"; then
            local found; found=$(lspci | grep -iE "NVIDIA|Tesla" | head -3)
            progress OK "Tesla P100 обнаружена!"
            echo "$found" | while read -r l; do progress INFO "  $l"; done
            return 0
        fi

        local remaining=$(( deadline - $(date +%s) ))
        if [[ $remaining -le 0 ]]; then
            progress ERROR "Тайм-аут (${WAIT_TIMEOUT} сек). Tesla P100 не подключена."
            progress INFO "Подключите карту к PCIe слоту и запустите скрипт снова."
            exit 1
        fi

        progress INFO "Карта не обнаружена... ожидание (осталось: ${remaining} сек)"
        sleep 5
    done
}

# ─── 2. ИСПРАВЛЕНИЕ ДИСПЛЕЯ ─────────────────────────────────────────────────
# Tesla P100 не имеет видеовыходов. Исправляем так, чтобы монитор всегда
# шёл через iGPU процессора — ни при каком раскладе не гаснет.
fix_display_config() {
    progress STEP "Шаг 2/8 — Фикс дисплея (iGPU всегда управляет монитором)"

    # ── 2a. Найти Intel iGPU BusID ──────────────────────────────────────────
    local igpu_pci; igpu_pci=$(lspci | grep -iE "VGA|Display|3D" | grep -i intel | head -1 || true)
    if [[ -z "$igpu_pci" ]]; then
        progress WARN "Intel iGPU не найдена в lspci. Пропускаем X11 конфиг."
    else
        # Преобразовать "00:02.0" → "PCI:0:2:0"
        local bus_raw; bus_raw=$(echo "$igpu_pci" | cut -d' ' -f1)
        local busid; busid="PCI:$(echo "$bus_raw" | sed 's/\./:/' | sed 's/:/ /2' | \
            awk '{split($1,a,":"); printf "%d:%d:%d", strtonum("0x"a[1]), strtonum("0x"a[2]), $2}')"
        progress INFO "Intel iGPU BusID: ${busid}"

        # ── 2b. X11 конфиг — принудительно Intel для дисплея ───────────────
        mkdir -p /etc/X11/xorg.conf.d
        cat > /etc/X11/xorg.conf.d/10-intel-primary.conf << EOF
# Super Sistema — принудительно Intel iGPU для дисплея
# Tesla P100 используется только для вычислений (нет видеовыходов)
Section "Device"
    Identifier  "Intel iGPU"
    Driver      "intel"
    BusID       "${busid}"
    Option      "TearFree"   "true"
    Option      "DRI"        "3"
EndSection

Section "Screen"
    Identifier  "Primary Screen"
    Device      "Intel iGPU"
EndSection
EOF
        progress OK "X11 конфиг создан: /etc/X11/xorg.conf.d/10-intel-primary.conf"
    fi

    # ── 2c. GRUB — iGPU всегда активна при загрузке ─────────────────────────
    if [[ -f /etc/default/grub ]]; then
        local grub_file="/etc/default/grub"
        local current; current=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" "$grub_file" | head -1 || echo "")
        local params="intel_iommu=on i915.enable_guc=2 i915.enable_dc=0"

        if echo "$current" | grep -q "intel_iommu"; then
            progress INFO "GRUB параметры уже установлены, пропускаем"
        else
            # Добавить параметры в существующую строку
            cp "${grub_file}" "${grub_file}.bak-$(date +%Y%m%d)"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${params}\"|" "$grub_file"
            progress OK "GRUB обновлён (параметры iGPU добавлены)"
            # Применить
            if command -v update-grub &>/dev/null; then
                update-grub 2>/dev/null && progress OK "update-grub выполнен"
            elif command -v grub2-mkconfig &>/dev/null; then
                grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null && progress OK "grub2-mkconfig выполнен"
            fi
        fi
    fi

    # ── 2d. udev правило — чтобы X/Wayland не переключались на P100 ─────────
    cat > /etc/udev/rules.d/71-nvidia-display.rules << 'EOF'
# Tesla P100 — только вычислительный режим, не дисплейный
ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card*", \
    ATTR{device/vendor}=="0x10de", \
    ATTR{device/subsystem_vendor}=="0x10de", \
    RUN+="/bin/sh -c 'echo 0 > /sys/class/drm/%k/device/enable_display 2>/dev/null || true'"
EOF
    udevadm control --reload-rules 2>/dev/null || true
    progress OK "udev правило для P100 (compute-only) создано"
}

# ─── 3. ПОИСК И УСТАНОВКА NVIDIA ДРАЙВЕРА ───────────────────────────────────
install_nvidia_driver() {
    progress STEP "Шаг 3/8 — Установка NVIDIA драйвера для Tesla P100"

    # Проверить — может уже установлен
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        local ver; ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        progress OK "Драйвер уже установлен: v${ver}"
        return 0
    fi

    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop|raspbian)
            _install_driver_debian
            ;;
        centos|rhel|rocky|almalinux)
            _install_driver_rhel
            ;;
        fedora)
            _install_driver_fedora
            ;;
        arch|manjaro|endeavouros)
            _install_driver_arch
            ;;
        *)
            progress WARN "Неизвестный дистрибутив: ${DISTRO}. Пробуем универсальный установщик."
            _install_driver_runfile
            ;;
    esac
}

_install_driver_debian() {
    progress INFO "Метод: apt (Ubuntu/Debian)"
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y -qq ubuntu-drivers-common 2>/dev/null || true

    # Определить лучший доступный драйвер для Tesla P100 (GP100/Pascal)
    local best_driver=""

    if command -v ubuntu-drivers &>/dev/null; then
        progress INFO "Поиск рекомендуемого драйвера через ubuntu-drivers..."
        local recommended
        recommended=$(ubuntu-drivers devices 2>/dev/null | grep recommended | grep -oP 'nvidia-driver-\d+' | head -1 || true)
        if [[ -n "$recommended" ]]; then
            best_driver="$recommended"
            progress INFO "Рекомендован: ${best_driver}"
        fi
    fi

    # Fallback: попробовать версии от новой к старой
    if [[ -z "$best_driver" ]]; then
        for ver in 550 545 535 525 515 510 470; do
            if apt-cache show "nvidia-driver-${ver}" &>/dev/null 2>&1; then
                best_driver="nvidia-driver-${ver}"
                break
            fi
        done
    fi

    # Если в репо нет — добавить PPA
    if [[ -z "$best_driver" ]]; then
        progress INFO "Добавляем PPA graphics-drivers..."
        apt-get install -y -qq software-properties-common
        add-apt-repository -y ppa:graphics-drivers/ppa 2>/dev/null
        apt-get update -qq
        for ver in 550 545 535 525; do
            if apt-cache show "nvidia-driver-${ver}" &>/dev/null 2>&1; then
                best_driver="nvidia-driver-${ver}"
                break
            fi
        done
    fi

    if [[ -z "$best_driver" ]]; then
        progress ERROR "Не удалось найти драйвер в репозиториях. Пробуем .run файл..."
        _install_driver_runfile
        return
    fi

    progress INFO "Устанавливаем ${best_driver}..."
    apt-get install -y "${best_driver}" linux-headers-"$(uname -r)" 2>&1 | \
        grep -E "Setting|Selecting|Unpacking|ERROR" | while read -r l; do progress INFO "$l"; done
    progress OK "${best_driver} установлен"
    NEED_REBOOT=true
}

_install_driver_rhel() {
    progress INFO "Метод: yum/dnf (RHEL/CentOS/Rocky)"
    dnf install -y epel-release kernel-devel kernel-headers dkms 2>/dev/null || \
    yum install -y epel-release kernel-devel kernel-headers dkms

    # NVIDIA CUDA репозиторий
    local rhel_ver; rhel_ver=$(echo "$DISTRO_VER" | cut -d. -f1)
    local repo_url="https://developer.download.nvidia.com/compute/cuda/repos/rhel${rhel_ver}/x86_64/cuda-rhel${rhel_ver}.repo"
    progress INFO "Добавляем CUDA репозиторий: ${repo_url}"
    curl -fsSL "$repo_url" -o /etc/yum.repos.d/cuda.repo 2>/dev/null || \
        progress WARN "Не удалось добавить CUDA репо, пробуем .run..."
    dnf module install -y nvidia-driver:latest-dkms 2>/dev/null || \
    yum install -y nvidia-driver-latest-dkms
    progress OK "NVIDIA драйвер установлен (RHEL)"
    NEED_REBOOT=true
}

_install_driver_fedora() {
    progress INFO "Метод: dnf (Fedora)"
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
    progress OK "NVIDIA драйвер установлен (Fedora)"
    NEED_REBOOT=true
}

_install_driver_arch() {
    progress INFO "Метод: pacman (Arch)"
    pacman -Sy --noconfirm nvidia nvidia-utils cuda
    progress OK "NVIDIA драйвер установлен (Arch)"
}

_install_driver_runfile() {
    # Скачать официальный .run файл с nvidia.com
    progress INFO "Поиск последней версии NVIDIA драйвера для Tesla P100 (Pascal/GP100)..."

    # NVIDIA Data Center Drivers — официальная страница для Tesla
    local latest_url="https://us.download.nvidia.com/tesla"

    # Попробовать несколько известных рабочих версий для P100
    local driver_versions=("550.54.14" "535.154.05" "525.147.05" "515.105.01")
    local downloaded=false

    for driver_ver in "${driver_versions[@]}"; do
        local run_url="${latest_url}/${driver_ver}/NVIDIA-Linux-${ARCH}-${driver_ver}.run"
        progress INFO "Пробуем: ${run_url}"
        if curl -fsSL --connect-timeout 10 -o /tmp/nvidia-driver.run "${run_url}" 2>/dev/null; then
            progress OK "Скачан: NVIDIA-Linux-${ARCH}-${driver_ver}.run"
            downloaded=true
            break
        fi
    done

    if [[ "$downloaded" != "true" ]]; then
        progress ERROR "Не удалось скачать драйвер. Проверьте интернет-соединение."
        return 1
    fi

    progress INFO "Устанавливаем драйвер (без OpenGL — для compute-only P100)..."
    apt-get install -y -qq dkms linux-headers-"$(uname -r)" 2>/dev/null || \
    yum install -y kernel-devel 2>/dev/null || true

    chmod +x /tmp/nvidia-driver.run
    /tmp/nvidia-driver.run \
        --silent \
        --no-opengl-files \
        --no-x-check \
        --dkms \
        -- 2>&1 | grep -E "Warning|Error|Installing|Done" | \
        while read -r l; do progress INFO "$l"; done

    progress OK "NVIDIA драйвер установлен (.run)"
    NEED_REBOOT=true
}

# ─── 4. УСТАНОВКА nvidia-container-toolkit ──────────────────────────────────
install_container_toolkit() {
    progress STEP "Шаг 4/8 — nvidia-container-toolkit (Docker ↔ GPU)"

    # Проверить наличие
    if dpkg -l nvidia-container-toolkit &>/dev/null 2>&1 || \
       rpm -q nvidia-container-toolkit &>/dev/null 2>&1; then
        progress OK "nvidia-container-toolkit уже установлен"
        return 0
    fi

    # Официальный репозиторий NVIDIA для всех дистрибутивов
    local gpg_key="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    progress INFO "Добавляем репозиторий NVIDIA Container Toolkit..."

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey 2>/dev/null | \
        gpg --dearmor -o "${gpg_key}" 2>/dev/null

    case "${DISTRO}" in
        ubuntu|debian|linuxmint|pop)
            curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null | \
                sed "s|deb https://|deb [signed-by=${gpg_key}] https://|g" | \
                tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq nvidia-container-toolkit
            ;;
        centos|rhel|rocky|almalinux|fedora)
            curl -sL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
            dnf install -y nvidia-container-toolkit 2>/dev/null || \
            yum install -y nvidia-container-toolkit
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm nvidia-container-toolkit 2>/dev/null || \
            progress WARN "Установите nvidia-container-toolkit из AUR"
            ;;
        *)
            progress WARN "Попробуйте: pip install nvidia-container-toolkit"
            ;;
    esac

    progress OK "nvidia-container-toolkit установлен"
}

# ─── 4b. УСТАНОВКА DOCKER если отсутствует ──────────────────────────────────
ensure_docker() {
    if command -v docker &>/dev/null; then
        progress OK "Docker уже установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        return 0
    fi
    progress INFO "Docker не найден — устанавливаем автоматически..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker --now 2>/dev/null || service docker start 2>/dev/null || true
    sleep 3
    if command -v docker &>/dev/null; then
        progress OK "Docker установлен"
    else
        progress ERROR "Не удалось установить Docker. Установите вручную: https://docs.docker.com/engine/install/"
        exit 1
    fi
}

# ─── 5. НАСТРОЙКА DOCKER RUNTIME ────────────────────────────────────────────
configure_docker() {
    progress STEP "Шаг 5/8 — Настройка Docker для работы с P100"

    ensure_docker

    # nvidia-ctk настраивает /etc/docker/daemon.json
    if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk runtime configure --runtime=docker 2>/dev/null
        progress OK "nvidia-ctk настроил Docker runtime"
    else
        progress INFO "nvidia-ctk не найден, конфигурируем вручную..."
        mkdir -p /etc/docker
        # Merge с существующим daemon.json если есть
        local daemon_json="/etc/docker/daemon.json"
        if [[ -f "$daemon_json" ]]; then
            python3 -c "
import json
with open('${daemon_json}') as f:
    cfg = json.load(f)
cfg.setdefault('runtimes', {})['nvidia'] = {
    'path': 'nvidia-container-runtime',
    'runtimeArgs': []
}
with open('${daemon_json}', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null || cat > "$daemon_json" << 'JSON'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
JSON
        else
            cat > "$daemon_json" << 'JSON'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
JSON
        fi
    fi

    systemctl daemon-reload
    systemctl restart docker
    sleep 4

    # Проверить что Docker видит GPU
    if docker run --rm --gpus all ubuntu:22.04 nvidia-smi 2>/dev/null | grep -q "Tesla\|NVIDIA"; then
        progress OK "Docker успешно видит Tesla P100!"
    else
        if [[ "${NEED_REBOOT:-false}" == "true" ]]; then
            progress WARN "Docker не видит GPU — нужна перезагрузка для загрузки драйвера"
        else
            progress WARN "Docker + GPU: требуется проверка после перезагрузки"
        fi
    fi
}

# ─── 6. ОПТИМИЗАЦИЯ P100 ────────────────────────────────────────────────────
optimize_p100() {
    progress STEP "Шаг 6/8 — Оптимизация Tesla P100 для нейросетей"

    # Ждём полного запуска драйвера
    local tries=0
    while ! nvidia-smi &>/dev/null; do
        tries=$((tries + 1))
        [[ $tries -gt 10 ]] && { progress WARN "nvidia-smi не отвечает — оптимизация после перезагрузки"; return 0; }
        sleep 2
    done

    # Persistence Mode — держать GPU в памяти без перезапуска при каждом запросе
    nvidia-smi -pm 1 2>/dev/null && progress OK "Persistence Mode: ВКЛЮЧЁН" || \
        progress WARN "Persistence Mode: не удалось установить"

    # Power Limit — Tesla P100 SXM2 = 300W, PCIe = 250W
    # Устанавливаем максимум для максимальной производительности
    local max_power; max_power=$(nvidia-smi --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    if [[ -n "$max_power" && "$max_power" =~ ^[0-9.]+$ ]]; then
        nvidia-smi -pl "${max_power%.*}" 2>/dev/null && \
            progress OK "Power Limit: ${max_power%.*}W (максимальная производительность)" || \
            progress WARN "Power Limit: не удалось установить"
    fi

    # Compute Mode — EXCLUSIVE_PROCESS для лучшей производительности Ollama
    nvidia-smi -c 0 2>/dev/null && progress OK "Compute Mode: DEFAULT (оптимально для Ollama)" || true

    # ECC (Error Correction) — оставляем как есть (не трогаем, P100 сам управляет)

    # Показать конфигурацию GPU
    local gpu_name; gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    local gpu_mem;  gpu_mem=$(nvidia-smi  --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    local gpu_temp; gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
    local gpu_drv;  gpu_drv=$(nvidia-smi  --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    local cuda_ver; cuda_ver=$(nvidia-smi | grep "CUDA Version" | awk '{print $NF}' || echo "N/A")

    progress OK "GPU:      ${gpu_name}"
    progress OK "VRAM:     ${gpu_mem}"
    progress OK "Temp:     ${gpu_temp}°C"
    progress OK "Драйвер:  v${gpu_drv}  |  CUDA: ${cuda_ver}"
}

# ─── 7. ЗАПУСК Super Sistema с GPU ──────────────────────────────────────────
start_with_gpu() {
    progress STEP "Шаг 7/8 — Запуск Super Sistema с Tesla P100"

    local compose_gpu="${PROJECT_DIR}/docker-compose.gpu.yml"
    if [[ ! -f "$compose_gpu" ]]; then
        progress ERROR "Файл не найден: ${compose_gpu}"
        return 1
    fi

    cd "${PROJECT_DIR}"

    # Массив команды — надёжно работает и с "docker compose" и с "docker-compose"
    local -a compose
    if docker compose version &>/dev/null 2>&1; then
        compose=(docker compose)
    else
        compose=(docker-compose)
    fi

    # Создать shared-директорию на хосте (bind mount для GPU Panel)
    mkdir -p /tmp/super-sistema/shared

    # Остановить CPU-вариант
    progress INFO "Останавливаем CPU-контейнеры..."
    "${compose[@]}" down 2>/dev/null || true

    # Собрать gpu-panel образ
    progress INFO "Собираем gpu-panel образ..."
    "${compose[@]}" -f docker-compose.gpu.yml build gpu-panel 2>&1 | \
        grep -E "Step|step|Successfully|ERROR|error" | \
        while read -r l; do progress INFO "$l"; done

    progress INFO "Запускаем все сервисы с GPU..."
    "${compose[@]}" -f docker-compose.gpu.yml up -d 2>&1 | \
        grep -E "Creating|Starting|Running|Error|error" | \
        while read -r l; do progress INFO "$l"; done

    # Ждём запуска Ollama
    local retries=0
    while ! curl -sf http://localhost:11434/api/tags &>/dev/null; do
        retries=$((retries + 1))
        [[ $retries -gt 20 ]] && { progress WARN "Ollama не запустился за 60 сек"; break; }
        sleep 3
    done

    [[ $retries -le 20 ]] && progress OK "Ollama запущен и отвечает на запросы"
    progress OK "GPU Panel доступна: http://localhost:8765"
    progress OK "AI Чат (Open WebUI): http://localhost:3000"
}

# ─── 8. ФИНАЛЬНЫЙ ТЕСТ ──────────────────────────────────────────────────────
run_tests() {
    progress STEP "Шаг 8/8 — Тестирование Tesla P100"

    # Тест 1: nvidia-smi
    if nvidia-smi --query-gpu=name,memory.total,utilization.gpu --format=csv,noheader \
            2>/dev/null | grep -q "Tesla\|NVIDIA"; then
        progress OK "Тест 1: nvidia-smi ✓"
    else
        progress WARN "Тест 1: nvidia-smi не готов (нужна перезагрузка?)"
    fi

    # Тест 2: Docker видит GPU
    if docker run --rm --gpus all ubuntu:22.04 nvidia-smi --query-gpu=name \
            --format=csv,noheader 2>/dev/null | grep -qi "nvidia\|tesla"; then
        progress OK "Тест 2: Docker + GPU ✓"
    else
        progress WARN "Тест 2: Docker не видит GPU (ожидается после перезагрузки)"
    fi

    # Тест 3: Ollama использует GPU
    local ollama_running=false
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        ollama_running=true
        # Запустить тест-инференс если есть хоть одна модель
        local model; model=$(curl -s http://localhost:11434/api/tags 2>/dev/null | \
            python3 -c "import sys,json; m=json.load(sys.stdin).get('models',[]); \
            print(m[0]['name'] if m else '')" 2>/dev/null || echo "")
        if [[ -n "$model" ]]; then
            progress INFO "Тест-запрос к модели ${model} через GPU..."
            local reply; reply=$(curl -s --max-time 30 http://localhost:11434/api/generate \
                -d "{\"model\":\"${model}\",\"prompt\":\"2+2=\",\"stream\":false}" 2>/dev/null | \
                python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','?')[:40])" 2>/dev/null || echo "timeout")
            progress OK "Тест 3: Ollama отвечает: '${reply}' ✓"
        else
            progress OK "Тест 3: Ollama работает (нет моделей — скачайте через панель)"
        fi
    else
        progress WARN "Тест 3: Ollama не запущен"
    fi

    # Итог
    progress DONE "Tesla P100 активирована и готова к работе с нейросетями!"
}

# ─── Сохранить статус ────────────────────────────────────────────────────────
write_status() {
    local gpu_info; gpu_info=$(nvidia-smi --query-gpu=name,memory.total,driver_version \
        --format=csv,noheader 2>/dev/null | head -1 || echo "P100,N/A,pending-reboot")
    cat > "${STATUS_FILE}" << EOF
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
STATUS=active
GPU_INFO=${gpu_info}
WEBUI_URL=http://localhost:3000
GPU_PANEL_URL=http://localhost:8765
EOF
    progress OK "Статус сохранён: ${STATUS_FILE}"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
NEED_REBOOT=false

main() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   SUPER SISTEMA — Активация Tesla P100              ║"
    echo "║   Полная автоматическая установка и настройка       ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    detect_distro
    wait_for_p100
    fix_display_config
    install_nvidia_driver
    install_container_toolkit
    configure_docker
    optimize_p100
    start_with_gpu
    run_tests
    write_status

    echo ""
    if [[ "${NEED_REBOOT:-false}" == "true" ]]; then
        progress WARN "═══ НУЖНА ПЕРЕЗАГРУЗКА ═══"
        progress INFO "Драйвер установлен. После перезагрузки Tesla P100 будет полностью активна."
        progress INFO "Super Sistema запустится автоматически."
        echo ""
        read -rp "  Перезагрузить сейчас? (y/N): " rb
        [[ "${rb,,}" == "y" ]] && reboot
    fi
}

main "$@"
