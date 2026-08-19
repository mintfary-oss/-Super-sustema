# Super Sistema — Полный план создания программы

## Описание проекта

**Super Sistema** — локальный AI-ассистент (чат + агент), работающий полностью без облаков и интернета.
Использует Open WebUI + Ollama. Поддерживает все популярные AI модели.

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
```

Всё работает в Docker-контейнерах. Нет интернета — нет проблем.

---

## Стек технологий

| Компонент    | Технология                             | Зачем                              |
|--------------|----------------------------------------|------------------------------------|
| AI движок    | Ollama                                 | Запускает модели локально          |
| Веб UI       | Open WebUI (ghcr.io/open-webui)        | Красивый интерфейс, как ChatGPT    |
| Контейнеры   | Docker Compose                         | Единое развёртывание               |
| Linux уст.   | Bash script (install.sh)               | Один файл — запустил — работает    |
| Windows уст. | PowerShell + NSIS (.exe)               | Установщик как нормальное ПО       |
| Конфиг       | .env файл                              | Все настройки в одном месте        |

---

## Поддерживаемые AI модели (через Ollama)

| Модель              | Размер  | Для чего                        |
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
super-sistema/
├── docker-compose.yml          # CPU-вариант (основной)
├── docker-compose.gpu.yml      # GPU NVIDIA вариант
├── .env.example                # Шаблон конфигурации
├── .env                        # Реальный конфиг (не в git)
├── install.sh                  # Установщик для Linux (одна команда)
├── uninstall.sh                # Удаление
├── scripts/
│   ├── download-models.sh      # Скачать набор моделей
│   └── update.sh               # Обновить всё
├── installer/
│   ├── setup.ps1               # PowerShell установщик для Windows
│   ├── setup.nsi               # NSIS скрипт (источник для .exe)
│   └── SuperSistema-Setup.exe  # Скомпилированный установщик
├── config/
│   └── nginx.conf              # (опционально) reverse proxy
├── docs/
│   ├── PLAN.md                 # Этот файл
│   ├── CONVERSATION.md         # Переписка с AI
│   ├── DONE.md                 # Что сделано
│   ├── TODO.md                 # Что осталось
│   └── ERRORS.md               # Ошибки и решения
└── README.md                   # Главная документация
```

---

## Этапы разработки

### Этап 1: Основа (ВЫПОЛНЕНО)
- [x] Структура проекта
- [x] docker-compose.yml (CPU)
- [x] docker-compose.gpu.yml (GPU)
- [x] .env.example
- [x] README.md

### Этап 2: Установщики (ВЫПОЛНЕНО)
- [x] install.sh для Linux
- [x] uninstall.sh
- [x] setup.ps1 для Windows
- [x] setup.nsi (NSIS скрипт для .exe)

### Этап 3: Скрипты управления (ВЫПОЛНЕНО)
- [x] download-models.sh
- [x] update.sh

### Этап 4: Документация (ВЫПОЛНЕНО)
- [x] PLAN.md
- [x] CONVERSATION.md
- [x] DONE.md
- [x] TODO.md
- [x] ERRORS.md

### Этап 5: Публикация
- [ ] Push в GitHub репозиторий
- [ ] GitHub Releases с .exe файлом
- [ ] README с badges и скриншотами

---

## Команды для работы

```bash
# Установка (Linux)
bash install.sh

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
