# Super Sistema — Локальный AI-ассистент

Локальный AI-чат-ассистент. Работает **без интернета и без облаков**.
Поддерживает все популярные AI модели (Llama, Mistral, DeepSeek, Qwen и другие).

---

## Установка

### Linux (Ubuntu, Debian, Arch, Manjaro, EndeavourOS, Fedora, CentOS и другие)

```bash
git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
cd super-sistema
bash install.sh
```

> **Важно:** клонировать нужно в `super-sistema` (с указанием имени папки).
> Команда `cd -Super-sustema` не работает — bash воспринимает `-S` как флаг.

Откройте браузер: **http://localhost:3000**

---

### Windows

**Вариант 1 — Установщик .exe** (рекомендуется):
```
Скачать: https://github.com/mintfary-oss/-Super-sustema/releases/latest
→ SuperSistema-Setup.exe → правая кнопка → Запуск от имени администратора
```

**Вариант 2 — Batch файл:**
```
installer\install.bat → правая кнопка → Запуск от имени администратора
```

**Вариант 3 — PowerShell (от администратора):**
```powershell
git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
cd super-sistema\installer
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

---

## Tesla P100 / NVIDIA GPU

```bash
git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
cd super-sistema
bash install.sh
docker compose -f docker-compose.gpu.yml up -d
```

Открыть GPU панель: **http://localhost:8765** → нажать **ВКЛЮЧИТЬ TESLA P100**

Скрипт сам:
- Обнаружит карту в PCIe
- Установит NVIDIA драйвер
- Настроит монитор (iGPU остаётся основным)
- Запустит Ollama с GPU

---

## Требования

| | Минимум | Рекомендуется |
|---|---|---|
| CPU | 4 ядра | 8 ядер |
| RAM | 8 GB | 16 GB |
| Диск | 20 GB | 50 GB |
| OS | Windows 10 / Ubuntu 20.04 | Windows 11 / Ubuntu 22.04 |

---

## Управление

```bash
# Запуск
docker compose up -d

# Остановка
docker compose down

# Логи
docker compose logs -f

# Обновление
bash scripts/update.sh
```

---

## AI Модели

```bash
bash scripts/download-models.sh
```

| Модель | Размер | Описание |
|--------|--------|----------|
| phi3:mini | 2.3 GB | Минимальные требования |
| llama3.2:3b | 2 GB | Быстрый старт |
| mistral:7b | 4.1 GB | Универсальный |
| deepseek-r1:7b | 4.7 GB | Логика и рассуждения |
| qwen2.5:7b | 4.7 GB | Русский язык |
| codellama:7b | 3.8 GB | Написание кода |
| llama3.1:8b | 4.7 GB | Лучший баланс |

---

## Удаление

**Linux:**
```bash
bash uninstall.sh
```

**Windows:**
```
Пуск → Программы и компоненты → Super Sistema → Удалить
```

---

## Лицензия

MIT License
