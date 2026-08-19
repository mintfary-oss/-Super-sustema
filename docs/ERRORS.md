# Ошибки и решения — Super Sistema

*Последнее обновление: Август 2026*

---

## Ошибки в процессе разработки

---

### ОШИБКА #1: NSIS не установлен на сервере

**Описание:**
```
NSIS: not installed
```

**Причина:** На сборочном Linux-сервере не установлен пакет `nsis`.

**Решение (принятое):** GitHub Actions для автосборки .exe на Windows runner:
```yaml
# .github/workflows/build-installer.yml
jobs:
  build-exe:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build NSIS installer
        run: makensis installer/setup.nsi
```

**Статус:** ✅ Решено — GitHub Actions собирает .exe, Release v1.0.0 опубликован.

---

### ОШИБКА #2: Docker не доступен на сборочном сервере

**Описание:**
```
Docker: not in PATH
```

**Причина:** Облачный агент Pulumi Neo не имеет Docker daemon.

**Решение:** Синтаксическая валидация docker-compose через `python3 -c "import yaml..."`.
Реальный запуск — на машине пользователя.

**Статус:** ✅ YAML валидация проходит. Docker Compose файлы корректны.

---

### ОШИБКА #3: Named volume вместо bind mount в docker-compose.gpu.yml

**Описание:** Хост-скрипт `watch-gpu.sh` писал файл-триггер в `/tmp/super-sistema/shared/`
на хосте, но `gpu-panel` контейнер читал из именованного тома Docker — разные хранилища.

**Код до исправления:**
```yaml
volumes:
  - gpu_shared:/shared
```

**Причина:** Named volume изолирован внутри Docker — хост и контейнер не видят одни файлы.

**Исправление:**
```yaml
volumes:
  - /tmp/super-sistema/shared:/shared  # bind mount — хост и контейнер в одной папке
```

**Статус:** ✅ Исправлено в сессии 14:13.

---

### ОШИБКА #4: SHARED_DIR игнорировал os.getenv() в app.py

**Описание:** Переменная окружения `SHARED_DIR` игнорировалась — путь всегда был `/shared`.

**Код до исправления:**
```python
SHARED_DIR = "/shared"  # жёстко прописан, env не работал
```

**Исправление:**
```python
SHARED_DIR = os.getenv("SHARED_DIR", "/shared")  # читает из env, fallback = /shared
```

**Статус:** ✅ Исправлено.

---

### ОШИБКА #5: Неверный счётчик позиций в /api/progress

**Описание:** `total` считался неправильно — при вызове `/api/progress?since=5`
возвращалось `total=5+5=10` вместо `total=5+<новые строки>`.

**Код до исправления:**
```python
total = since + since + len(lines)   # BUG: since добавлялся дважды
```

**Исправление:**
```python
total = since + len(lines)   # FIX: правильный счётчик позиции
```

**Статус:** ✅ Исправлено.

---

### ОШИБКА #6: Dockerfile не создавал /shared и не устанавливал pciutils

**Описание:**
- `/shared` не создавался → bind mount мог не монтироваться корректно
- `pciutils` (нужен для `lspci`) не устанавливался → `/api/status` возвращал пустой `pcie`

**Исправление:**
```dockerfile
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends pciutils curl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /shared
```

**Статус:** ✅ Исправлено.

---

### ОШИБКА #7: `local` вне функции в watch-gpu.sh

**Описание:**
```
watch-gpu.sh: line 171: local: can only be used in a function
```
`local -a _dc` использовалась в основном цикле `while` вне функции.

**Исправление:**
```bash
# Было:
local -a _dc
# Стало:
_dc=()
...
unset _dc
```

**Статус:** ✅ Исправлено.

---

### ОШИБКА #8: docker compose как строка вместо массива

**Описание:** В `setup-tesla-p100.sh` и `watch-gpu.sh` команда `docker compose` использовалась
как строка: `compose="docker compose"` → `$compose up -d` → word splitting-проблемы в bash.

**Исправление:**
```bash
# Стало: массив — надёжно работает в любом bash
local -a compose
if docker compose version &>/dev/null 2>&1; then
    compose=(docker compose)
else
    compose=(docker-compose)
fi
"${compose[@]}" up -d
```

**Статус:** ✅ Исправлено.

---

### ОШИБКА #10: `cd -Super-sustema` — "invalid option"

**Описание:**
```
-bash: cd: -S: invalid option
cd: usage: cd [-L|[-P [-e]]] [-@] [dir]
bash: install.sh: No such file or directory
```

**Причина:** Имя папки начинается с `-` (минуса). Bash принимает `-Super-sustema` за флаги команды `cd`. Флаг `-S` не существует — ошибка.

**Воспроизводится:**
```bash
git clone https://github.com/mintfary-oss/-Super-sustema.git
cd -Super-sustema   # ← ОШИБКА: bash читает -S как флаг
```

**Исправление:** При клонировании указывать целевое имя папки без минуса:
```bash
git clone https://github.com/mintfary-oss/-Super-sustema.git super-sistema
cd super-sistema    # ← РАБОТАЕТ
bash install.sh
```

**Исправлено в:** README.md, USERGUIDE.md, PLAN.md, все документы — везде исправлена команда клонирования.

**Статус:** ✅ Исправлено.

---

## Известные ограничения

| Ограничение | Описание | Обходное решение |
|-------------|----------|-----------------|
| AMD GPU | Нет docker-compose.amd.yml с ROCm | CPU вариант |
| macOS GPU | Docker не поддерживает Metal GPU | Ollama на CPU |
| Windows Home | Docker Desktop требует WSL2 | Включить WSL2 |
| Tesla P100 горячее подключение | Требует поддержки PCIe hotplug в BIOS | Подключить при выключенном ПК |
| .exe установщик | Нет кастомной иконки | Используется системная |
| Большие модели (70B+) | Требуют много VRAM / RAM | Использовать меньшие модели |

---

## Частые вопросы (FAQ)

### Почему модель отвечает медленно?
- На CPU: 1–10 токен/сек — это нормально
- Используйте меньшую модель: `phi3:mini`, `llama3.2:3b`
- С Tesla P100: 30–100 токен/сек

### Ошибка "port 3000 already in use"
```bash
sudo lsof -i :3000           # найти что занимает
echo "WEBUI_PORT=3001" >> .env
docker compose up -d
```

### GPU Panel не видит P100 после активации
1. Перезагрузите ПК (после установки драйвера нужна перезагрузка)
2. Проверьте: `nvidia-smi` — должна показать Tesla P100
3. Перезапустите GPU Panel: `docker compose -f docker-compose.gpu.yml restart gpu-panel`

### Монитор гаснет при подключении Tesla P100
Скрипт настраивает GRUB и X11 автоматически (Шаг 2/8). Если не помогло:
- В BIOS: `Primary Display → IGFX` (или Integrated / CPU Graphics)
- Это нужно сделать один раз

### Как добавить OpenAI API
В Open WebUI: `Settings → Connections → OpenAI API → вставьте ключ`

### Ошибка "no space left on device"
```bash
docker exec super-sistema-ollama ollama rm <имя-модели>
docker system prune -f
```
