#!/usr/bin/env bash
# Super Sistema — Скачать AI модели
# Использование: bash scripts/download-models.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OLLAMA_CONTAINER="super-sistema-ollama"

check_ollama() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
        echo -e "${RED}Контейнер ${OLLAMA_CONTAINER} не запущен.${NC}"
        echo "Запустите: docker compose up -d"
        exit 1
    fi
}

pull_model() {
    local model="$1"
    local size="$2"
    echo -e "${BLUE}[Скачиваем]${NC} ${model} (~${size})..."
    docker exec "${OLLAMA_CONTAINER}" ollama pull "${model}"
    echo -e "${GREEN}[Готово]${NC}    ${model}"
}

show_menu() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║      SUPER SISTEMA — Скачать AI модели               ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Выберите набор моделей для скачивания:"
    echo ""
    echo "  1) Минимальный (2 GB)"
    echo "     └─ phi3:mini — быстрый, мало RAM"
    echo ""
    echo "  2) Стандартный (11 GB) — РЕКОМЕНДУЕТСЯ"
    echo "     ├─ llama3.2:3b  — быстрый баланс"
    echo "     ├─ mistral:7b   — универсальный"
    echo "     └─ deepseek-r1:7b — логика и рассуждения"
    echo ""
    echo "  3) Полный (25 GB)"
    echo "     ├─ llama3.1:8b  — лучший баланс"
    echo "     ├─ qwen2.5:7b   — русский язык"
    echo "     ├─ codellama:7b — написание кода"
    echo "     ├─ gemma2:9b    — Google модель"
    echo "     └─ deepseek-r1:7b"
    echo ""
    echo "  4) Только русский язык"
    echo "     └─ qwen2.5:7b — лучшая русскоязычная модель"
    echo ""
    echo "  5) Только для кода"
    echo "     ├─ codellama:7b"
    echo "     └─ deepseek-coder:6.7b"
    echo ""
    echo "  6) Ввести название модели вручную"
    echo "  7) Показать установленные модели"
    echo "  0) Выход"
    echo ""
}

show_installed() {
    echo -e "\n${CYAN}Установленные модели:${NC}"
    docker exec "${OLLAMA_CONTAINER}" ollama list
    echo ""
}

main() {
    check_ollama

    while true; do
        show_menu
        read -rp "Ваш выбор (0-7): " choice

        case "${choice}" in
            1)
                echo ""
                pull_model "phi3:mini" "2.3 GB"
                ;;
            2)
                echo ""
                pull_model "llama3.2:3b"    "2 GB"
                pull_model "mistral:7b"     "4.1 GB"
                pull_model "deepseek-r1:7b" "4.7 GB"
                ;;
            3)
                echo ""
                pull_model "llama3.1:8b"    "4.7 GB"
                pull_model "qwen2.5:7b"     "4.7 GB"
                pull_model "codellama:7b"   "3.8 GB"
                pull_model "gemma2:9b"      "5.4 GB"
                pull_model "deepseek-r1:7b" "4.7 GB"
                ;;
            4)
                echo ""
                pull_model "qwen2.5:7b" "4.7 GB"
                ;;
            5)
                echo ""
                pull_model "codellama:7b"        "3.8 GB"
                pull_model "deepseek-coder:6.7b" "3.8 GB"
                ;;
            6)
                echo ""
                read -rp "Введите название модели (пример: llama3.1:8b): " custom_model
                if [[ -n "${custom_model}" ]]; then
                    pull_model "${custom_model}" "?"
                fi
                ;;
            7)
                show_installed
                ;;
            0)
                echo "Выход."
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Введите 0-7.${NC}"
                ;;
        esac

        echo ""
        echo -e "${GREEN}${BOLD}Готово!${NC} Откройте http://localhost:3000 и выберите модель в чате."
        echo ""
        read -rp "Скачать ещё? (y/N): " again
        [[ "${again,,}" == "y" ]] || break
    done
}

main "$@"
