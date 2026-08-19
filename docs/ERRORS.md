# Ошибки и решения — Super Sistema

---

## Ошибки в процессе разработки

---

### ОШИБКА #1: NSIS не установлен на сервере

**Описание:**
```
NSIS: not installed
```

**Причина:** На сборочном Linux-сервере не установлен пакет `nsis`.

**Решение 1 (рекомендуется):** Использовать GitHub Actions для сборки .exe:
```yaml
# .github/workflows/build-installer.yml
name: Build Installer
on: [push]
jobs:
  build-exe:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build NSIS installer
        run: makensis installer/setup.nsi
```

**Решение 2:** Установить NSIS вручную:
```bash
# Ubuntu/Debian
sudo apt-get install nsis

# Затем компилировать:
makensis installer/setup.nsi
```

**Статус:** Обходное решение — NSIS скрипт создан, .exe будет собран через GitHub Actions.

---

### ОШИБКА #2: Docker не доступен в текущем окружении

**Описание:**
```
Docker: not in PATH
```

**Причина:** Сборочный сервер (облачный агент Pulumi Neo) не имеет Docker daemon.

**Решение:** Тестирование docker-compose выполняется синтаксически.
Реальный запуск — на машине пользователя после установки Docker.

**Статус:** Файлы Docker Compose корректны синтаксически, готовы к запуску.

---

### ОШИБКА #3: sudo недоступен в окружении

**Описание:**
```
/bin/bash: line 1: sudo: command not found
```

**Причина:** Контейнеризированное окружение без sudo.

**Решение:** Адаптированы скрипты — проверка наличия sudo в install.sh,
добавлен fallback без sudo.

**Статус:** Решено в коде install.sh.

---

## Известные ограничения

| Ограничение                     | Описание                                           | Обходное решение                    |
|---------------------------------|----------------------------------------------------|-------------------------------------|
| GPU на macOS (M1/M2/M3)         | Docker не поддерживает Metal GPU                   | Ollama работает на CPU              |
| AMD GPU                         | Нужен отдельный docker-compose.amd.yml с ROCm      | Используйте CPU вариант            |
| Windows Home Edition            | Docker Desktop требует WSL2                        | Включить WSL2 в Windows Features   |
| Антивирус блокирует Docker      | Windows Defender/Kaspersky/ESET                    | Добавить исключение для Docker      |
| Модели больше RAM               | OOM (Out of Memory) при запуске                    | Выбрать меньшую модель              |

---

## Частые вопросы (FAQ)

### Почему модель отвечает медленно?
- На CPU: скорость ~1-10 токен/сек — это нормально
- Решение: используйте меньшую модель (phi3:mini, llama3.2:3b)
- С GPU: скорость 30-100 токен/сек

### Ошибка "port 3000 already in use"
```bash
# Найти что занимает порт
sudo lsof -i :3000
# Изменить порт в .env файле
echo "WEBUI_PORT=3001" >> .env
docker compose up -d
```

### Как добавить OpenAI API ключ?
В Open WebUI: Settings → Connections → OpenAI API → вставьте ключ.
Тогда будут доступны GPT-4, GPT-3.5 и т.д.

### Ошибка "no space left on device"
Модели занимают место. Удалите ненужные:
```bash
docker exec super-sistema-ollama ollama rm llama3.1:70b
```

### Контейнер не запускается на Windows
1. Убедитесь что Docker Desktop запущен
2. В Docker Desktop: Settings → Resources → WSL Integration → включите
3. Перезапустите Docker Desktop
