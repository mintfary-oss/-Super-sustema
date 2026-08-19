# Что ещё надо сделать — Super Sistema

## Текущий статус

---

## 🔲 Ожидает выполнения

### Публикация
- [ ] Получить новый GitHub токен от пользователя (старый скомпрометирован)
- [ ] Git init + remote add origin
- [ ] Push всего кода в `mintfary-oss/-Super-sustema`
- [ ] Создать GitHub Release с тегом v1.0.0
- [ ] Прикрепить `SuperSistema-Setup.exe` к Release
- [ ] Добавить скриншоты в README

### Компиляция .exe
- [ ] Установить NSIS на машину сборки (или использовать GitHub Actions)
- [ ] Скомпилировать `installer/setup.nsi` → `SuperSistema-Setup.exe`
- [ ] Протестировать .exe на Windows-машине

### Опционально (улучшения)
- [ ] Добавить nginx reverse proxy с HTTPS
- [ ] Создать systemd service для автозапуска (Linux)
- [ ] Добавить Windows Service для автозапуска
- [ ] Добавить поддержку AMD GPU (ROCm)
- [ ] Создать docker-compose.amd.yml
- [ ] Добавить мониторинг (Portainer)
- [ ] Создать Makefile для удобного управления

---

## 📋 Приоритеты

| Приоритет | Задача                                    | Важность |
|-----------|-------------------------------------------|----------|
| 1         | Получить новый GitHub токен               | 🔴 КРИТИЧНО |
| 2         | Push кода в репозиторий                   | 🔴 Высокий |
| 3         | Компиляция .exe через GitHub Actions      | 🟡 Средний |
| 4         | Nginx + HTTPS                             | 🟢 Низкий |
| 5         | AMD GPU поддержка                         | 🟢 Низкий |

---

## 🚫 Блокеры

1. **GitHub токен** — токен был опубликован в открытой переписке и должен быть
   немедленно отозван: https://github.com/settings/tokens
   Нужен новый токен с правами `repo` для пуша в репозиторий.

2. **NSIS** — не установлен на текущем сервере. Для компиляции .exe нужно:
   - Установить NSIS на Windows-машину и скомпилировать там, ИЛИ
   - Использовать GitHub Actions (рекомендуется) — автоматически компилирует при push

---

## 💡 Решение блокера с NSIS

Добавить GitHub Actions workflow для автосборки .exe:

```yaml
# .github/workflows/build-installer.yml
name: Build Windows Installer
on:
  push:
    tags:
      - 'v*'
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Compile NSIS installer
        run: makensis installer/setup.nsi
      - name: Upload to Release
        uses: softprops/action-gh-release@v1
        with:
          files: installer/SuperSistema-Setup.exe
```
