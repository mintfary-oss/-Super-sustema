# Super Sistema — Полный план создания программы

## Описание проекта

**Super Sistema** — локальный AI-ассистент (чат + агент), работающий полностью без облаков и интернета.
Использует Open WebUI + Ollama + GPU Panel для Tesla P100. Поддерживает все популярные AI модели.

---

## Архитектура

```
[Браузер пользователя]
        │
        ▼
[Open WebUI :3000]  ─── веб-интерфейс (как ChatGPT, но локальный)
        │
        ▼
[Ollama :11434]  ─── движок для запуска AI моделей локально
        │
        ▼
[AI Модели]  ─── llama3, mistral, deepseek, phi3, qwen2, codellama...

[GPU Panel :8765]  ─── кнопка ВКЛЮЧИТЬ TESLA P100 + live мониторинг
        │
        ▼
[setup-tesla-p100.sh]  ─── авто-установка драйверов + оптимизация P100
```

Всё работает в Docker-контейнерах. Нет интернета — нет проблем.

---

## Стек технологий

| Компонент    | Технология                             | Зачем                              |
|--------------|----------------------------------------|------------------------------------|
| AI движок    | Ollama                                 | Запускает модели локально          |
| Веб UI       | Open WebUI (ghcr.io/open-webui)        | Красивый интерфейс, как ChatGPT    |
| GPU Panel    | FastAPI + Jinja2 (gpu-panel/app.py)    | Кнопка P100 + SSE мониторинг       |
| Контейнеры   | Docker Compose                         | Единое развёртывание               |
| Linux уст.   | Bash script (install.sh)               | Один файл — запустил — работает    |
| Windows уст. | PowerShell + NSIS (.exe)               | Установщик как нормальное ПО       |
| Конфиг       | .env файл                              | Все настройки в одном месте        |

---

## Поддерживаемые AI модели (через Ollama)

| Модель              | Размер  | Для чего                         |
|---------------------|---------|----------------------------------|
| llama3.2:3b         | 2 GB    | Быстрые ответы, мало RAM         |
| llama3.1:8b         | 4.7 GB  | Оптимальный баланс               |
| mistral:7b          | 4.1 GB  | Лёгкий и быстрый                 |
| deepseek-r1:7b      | 4.7 GB  | Рассуждения, логика              |
| qwen2.5:7b          | 4.7 GB  | Мультиязычный (включая русский)  |
| phi3:mini           | 2.3 GB  | Минимальные требования           |
| codellama:7b        | 3.8 GB  | Написание кода                   |
| gemma2:9b           | 5.4 GB  | Google модель                    |
| llama3.1:70b        | 40 GB   | Максимальное качество (нужно GPU)|

---

## Требования к железу

| Сценарий        | CPU          | RAM    | Диск  |
|-----------------|--------------|--------|-------|
| Минимальный     | 4 ядра       | 8 GB   | 20 GB |
| Рекомендуемый   | 8 ядер       | 16 GB  | 50 GB |
| С GPU           | 4 ядра + GPU | 16 GB  | 50 GB |

---

## Файловая структура проекта

```
super-sistema/                       ← клонировать: git clone ... super-sistema
├── docker-compose.yml               # CPU вариант (основной)
├── docker-compose.gpu.yml           # GPU NVIDIA + Tesla P100 вариант
├── .env.example                     # Шаблон конфигурации
├── .env                             # Реальный конфиг (создаётся при установке)
├── install.sh                       # Установщик для Linux (одна команда) v1.1
├── uninstall.sh                     # Удаление
├── gpu-panel/                       # Tesla P100 веб-панель
│   ├── app.py                       # FastAPI: кнопка + статус + SSE
│   ├── Dockerfile                   # python:3.12-slim
│   ├── requirements.txt             # fastapi, uvicorn, httpx, jinja2
│   └── templates/index.html         # Интерфейс кнопки и мониторинга
├── scripts/
│   ├── download-models.sh           # Скачать набор моделей (меню)
│   ├── update.sh                    # Обновить всё
│   ├── setup-tesla-p100.sh          # Авто-установка Tesla P100 (8 шагов)
│   ├── watch-gpu.sh                 # Мониторинг горячего подключения GPU
│   └── install-gpu-monitor.sh       # Установка watch-gpu как systemd сервис
├── installer/
│   ├── install.bat                  # Windows BAT установщик (двойной клик)
│   ├── setup.ps1                    # Windows PowerShell установщик
│   └── setup.nsi                    # NSIS скрипт (источник для .exe)
├── docs/
│   ├── PLAN.md                      # Этот файл
│   ├── CONVERSATION.md              # Переписка с AI
│   ├── DONE.md                      # Что сделано
│   ├── TODO.md                      # Что осталось
│   ├── ERRORS.md                    # Ошибки и решения
│   ├── TECHNICAL.md                 # Техническая документация
│   ├── USERGUIDE.md                 # Руководство пользователя
│   └── REPORT.md                    # Отчёт по проекту
├── .github/workflows/
│   └── build-installer.yml          # CI/CD: сборка .exe при git tag v*
├── .gitignore
├── LICENSE
└── README.md
```

---

## Этапы разработки

### Этап 1: Основа (ВЫПОЛНЕНО ✅)
- [x] Структура проекта
- [x] docker-compose.yml (CPU)
- [x] docker-compose.gpu.yml (GPU + Tesla P100)
- [x] .env.example
- [x] README.md

### Этап 2: Установщики (ВЫПОЛНЕНО ✅)
- [x] install.sh для Linux (Ubuntu/Debian/CentOS/Fedora/Arch/Manjaro/EndeavourOS/Garuda/ArcoLinux)
- [x] uninstall.sh
- [x] setup.ps1 для Windows
- [x] setup.nsi (NSIS скрипт для .exe)
- [x] install.bat для Windows

### Этап 3: Скрипты управления (ВЫПОЛНЕНО ✅)
- [x] download-models.sh
- [x] update.sh

### Этап 4: Tesla P100 поддержка (ВЫПОЛНЕНО ✅)
- [x] scripts/setup-tesla-p100.sh — 8-шаговая авто-установка
- [x] scripts/watch-gpu.sh — мониторинг горячего подключения
- [x] scripts/install-gpu-monitor.sh — systemd сервис
- [x] gpu-panel/app.py — FastAPI веб-панель
- [x] gpu-panel/templates/index.html — кнопка + live прогресс

### Этап 5: Документация (ВЫПОЛНЕНО ✅)
- [x] PLAN.md, CONVERSATION.md, DONE.md, TODO.md, ERRORS.md
- [x] TECHNICAL.md, USERGUIDE.md, REPORT.md

### Этап 6: Публикация и CI/CD (ВЫПОЛНЕНО ✅)
- [x] Push в GitHub репозиторий
- [x] GitHub Actions — сборка .exe при git tag v*
- [x] GitHub Releases v1.0.0 с SuperSistema-Setup.exe
- [x] GitHub Releases v1.1.0 — исправлены 9 багов установщиков

### Этап 7: Исправление багов v1.1 (ВЫПОЛНЕНО ✅)
- [x] Arch Linux: добавлены EndeavourOS, Garuda, ArcoLinux
- [x] Arch: убран docker-compose v1 (устаревший)
- [x] install.sh: COMPOSE_CMD → массив DC
- [x] install.sh: правильная обработка --skip-group
- [x] setup.nsi: убран Linux uninstall.sh, добавлен setup.ps1
- [x] setup.nsi: docker compose с cd /d $INSTDIR
- [x] install.bat: retry loop вместо hardcoded timeout
- [x] setup.ps1: PSScriptRoot вместо MyInvocation.ScriptName
- [x] README: исправлена команда клонирования (cd -Super-sustema → super-sistema)

---

## Команды для работы

```bash
# Клонирование и установка (Linux)
git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
cd super-sistema
bash install.sh

# GPU вариант (Tesla P100 / NVIDIA)
docker compose -f docker-compose.gpu.yml up -d
# Открыть http://localhost:8765 → ВКЛЮЧИТЬ TESLA P100

# Запуск
docker compose up -d

# Остановка
docker compose down

# Скачать модели
bash scripts/download-models.sh

# Обновить
bash scripts/update.sh

# Просмотр логов
docker compose logs -f

# Статус
docker compose ps
```
