# Super Sistema — Локальный AI-ассистент

Локальный AI-чат-ассистент. Работает **без интернета и без облаков**.
Поддерживает все популярные AI модели (Llama, Mistral, DeepSeek, Qwen и другие).

## Быстрая установка

### Linux (Ubuntu, Debian, CentOS, Fedora, Arch)

```bash
git clone https://github.com/mintfary-oss/-Super-sustema.git
cd -Super-sustema
bash install.sh
```

Откройте браузер: **http://localhost:3000**

---

### Windows

**Вариант 1 — Установщик .exe** (скачайте с [Releases](../../releases)):
```
SuperSistema-Setup.exe → правая кнопка → Запуск от имени администратора
```

**Вариант 2 — Batch файл** (не нужен .exe):
```
installer/install.bat → правая кнопка → Запуск от имени администратора
```

**Вариант 3 — PowerShell**:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\installer\setup.ps1
```

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

После установки откройте интерфейс и скачайте нужную модель:

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

## GPU (NVIDIA)

```bash
# Запуск с поддержкой NVIDIA GPU
docker compose -f docker-compose.gpu.yml up -d
```

Требуется: NVIDIA драйвер + [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

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
