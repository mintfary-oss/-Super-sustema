@echo off
setlocal EnableDelayedExpansion
:: Super Sistema — Установщик для Windows (BAT версия)
:: Запустите от имени администратора (правая кнопка → Запуск от имени администратора)
:: Или загрузите SuperSistema-Setup.exe с GitHub Releases для GUI-установщика

title Super Sistema — Установка

color 0B
echo.
echo ============================================================
echo        SUPER SISTEMA — Локальный AI-ассистент
echo        Работает без интернета и облаков
echo ============================================================
echo.

:: Проверка прав администратора
net session >nul 2>&1
if %errorLevel% neq 0 (
    color 0C
    echo [ОШИБКА] Требуются права администратора!
    echo Кликните правой кнопкой на install.bat
    echo и выберите "Запуск от имени администратора"
    pause
    exit /b 1
)

echo [OK] Права администратора подтверждены.
echo.

:: Проверка Docker
echo [INFO] Проверяем Docker...
docker --version >nul 2>&1
if %errorLevel% neq 0 (
    echo [WARN] Docker не найден!
    echo.
    echo Для работы Super Sistema необходим Docker Desktop.
    echo.
    set /p INSTALL_DOCKER="Открыть страницу загрузки Docker Desktop? (y/N): "
    if /i "%INSTALL_DOCKER%"=="y" (
        start https://www.docker.com/products/docker-desktop/
        echo.
        echo После установки Docker Desktop:
        echo  1. Запустите Docker Desktop
        echo  2. Дождитесь полной загрузки (значок в трее)
        echo  3. Запустите install.bat снова
    )
    pause
    exit /b 1
)

docker --version
echo [OK] Docker найден.
echo.

:: Определяем директорию
set SCRIPT_DIR=%~dp0
set PROJECT_DIR=%SCRIPT_DIR%..

:: Переходим в директорию проекта
cd /d "%PROJECT_DIR%"

:: Проверяем наличие docker-compose.yml
if not exist "docker-compose.yml" (
    echo [ОШИБКА] Файл docker-compose.yml не найден в: %PROJECT_DIR%
    echo Убедитесь что запускаете install.bat из папки проекта.
    pause
    exit /b 1
)

:: Создаём .env если нет
if not exist ".env" (
    echo [INFO] Создаём файл конфигурации .env...
    echo WEBUI_SECRET_KEY=super-sistema-%RANDOM%%RANDOM% > .env
    echo WEBUI_PORT=3000 >> .env
    echo WEBUI_AUTH=false >> .env
    echo OLLAMA_KEEP_ALIVE=24h >> .env
    echo OLLAMA_NUM_PARALLEL=1 >> .env
    echo OLLAMA_MAX_LOADED_MODELS=1 >> .env
    echo DEFAULT_MODELS=llama3.2:3b >> .env
    echo [OK] Файл .env создан.
)

echo.
echo [INFO] Скачиваем Docker образы (5-10 минут при первом запуске)...
docker compose pull
if %errorLevel% neq 0 (
    echo [ОШИБКА] Не удалось скачать образы. Проверьте интернет-соединение.
    pause
    exit /b 1
)

echo.
echo [INFO] Запускаем контейнеры...
docker compose up -d
if %errorLevel% neq 0 (
    echo [ОШИБКА] Не удалось запустить контейнеры.
    echo Проверьте логи: docker compose logs
    pause
    exit /b 1
)

echo [OK] Контейнеры запущены.
echo.
echo [INFO] Скачиваем стартовую модель AI (llama3.2:3b ~2GB)...
echo        Ожидаем запуска Ollama...

:: Ждём готовности Ollama (до 90 секунд, проверка каждые 3 сек)
set OLLAMA_READY=0
for /L %%i in (1,1,30) do (
    if not "!OLLAMA_READY!"=="1" (
        docker exec super-sistema-ollama ollama list >nul 2>&1 && set OLLAMA_READY=1
        if not "!OLLAMA_READY!"=="1" (
            echo [INFO] Попытка %%i/30 - ожидаем Ollama...
            timeout /t 3 /nobreak >nul
        )
    )
)
if not "!OLLAMA_READY!"=="1" (
    echo [WARN] Ollama не ответил за 90 сек. Скачайте модель вручную:
    echo        docker exec super-sistema-ollama ollama pull llama3.2:3b
    goto :skip_model
)
echo [INFO] Ollama готов. Скачиваем llama3.2:3b...
docker exec super-sistema-ollama ollama pull llama3.2:3b
:skip_model

:: Создаём ярлык на рабочем столе
echo.
echo [INFO] Создаём ярлык на рабочем столе...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%USERPROFILE%\Desktop\Super Sistema.url'); $s.TargetPath = 'http://localhost:3000'; $s.Save()"

echo.
color 0A
echo ============================================================
echo           УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!
echo ============================================================
echo.
echo   Откройте браузер: http://localhost:3000
echo.
echo   Управление:
echo     Запуск:    docker compose up -d
echo     Остановка: docker compose down
echo     Логи:      docker compose logs -f
echo.

:: Открываем браузер
timeout /t 3 /nobreak >nul
start http://localhost:3000

pause
