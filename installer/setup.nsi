; Super Sistema — NSIS Установщик для Windows
; Компиляция: makensis setup.nsi  (или через GitHub Actions)
; Требует NSIS 3.x: https://nsis.sourceforge.io/
;
; Результат: SuperSistema-Setup.exe

;=============================================================================
; Настройки компилятора
;=============================================================================
!define PRODUCT_NAME        "Super Sistema"
!define PRODUCT_VERSION     "1.0.0"
!define PRODUCT_PUBLISHER   "Super Sistema"
!define PRODUCT_WEB_SITE    "https://github.com/mintfary-oss/-Super-sustema"
!define PRODUCT_UNINST_KEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"
!define INSTALL_DIR         "$PROGRAMFILES64\Super Sistema"
!define WEBUI_PORT          "3000"

; Современный UI
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"

;=============================================================================
; Настройки установщика
;=============================================================================
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "SuperSistema-Setup.exe"
InstallDir "${INSTALL_DIR}"
InstallDirRegKey HKLM "Software\${PRODUCT_NAME}" ""
RequestExecutionLevel admin
ShowInstDetails show
ShowUnInstDetails show

; Сжатие
SetCompressor /SOLID lzma
SetCompressorDictSize 32

;=============================================================================
; Интерфейс
;=============================================================================
!define MUI_ABORTWARNING
!define MUI_ICON "..\assets\icon.ico"
!define MUI_UNICON "..\assets\icon.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "..\assets\wizard.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "..\assets\wizard.bmp"
!define MUI_WELCOMEPAGE_TITLE "Добро пожаловать в ${PRODUCT_NAME}"
!define MUI_WELCOMEPAGE_TEXT "Этот мастер установит ${PRODUCT_NAME} ${PRODUCT_VERSION} на ваш компьютер.$\r$\n$\r$\nLocalный AI-ассистент — работает без интернета и без облаков.$\r$\n$\r$\nНажмите 'Далее' для продолжения."

; Страницы установщика
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Super Sistema установлен!"
!define MUI_FINISHPAGE_TEXT "Установка завершена.$\r$\n$\r$\nОткройте браузер и перейдите по адресу:$\r$\nhttp://localhost:${WEBUI_PORT}"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Открыть Super Sistema в браузере"
!define MUI_FINISHPAGE_RUN_FUNCTION "OpenBrowser"
!define MUI_FINISHPAGE_SHOWREADME ""
!insertmacro MUI_PAGE_FINISH

; Страницы удалятора
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Язык
!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

;=============================================================================
; Функции
;=============================================================================

; Открыть браузер
Function OpenBrowser
    ExecShell "open" "http://localhost:${WEBUI_PORT}"
FunctionEnd

; Проверка Windows версии
Function CheckWindowsVersion
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_ICONSTOP "Требуется Windows 10 или новее."
        Abort
    ${EndIf}
FunctionEnd

; Проверка Docker
Function CheckDocker
    nsExec::ExecToStack 'docker --version'
    Pop $0
    ${If} $0 != "0"
        MessageBox MB_ICONEXCLAMATION|MB_YESNO \
            "Docker Desktop не найден.$\r$\n$\r$\nDocker Desktop необходим для работы Super Sistema.$\r$\n$\r$\nОткрыть страницу загрузки Docker Desktop?" \
            IDNO skip_docker
        ExecShell "open" "https://www.docker.com/products/docker-desktop/"
        MessageBox MB_ICONINFORMATION \
            "После установки Docker Desktop запустите его и дождитесь загрузки.$\r$\nЗатем снова запустите этот установщик."
        Abort
        skip_docker:
    ${EndIf}
FunctionEnd

; Инициализация
Function .onInit
    Call CheckWindowsVersion
    Call CheckDocker
FunctionEnd

;=============================================================================
; Секция установки
;=============================================================================
Section "Super Sistema (обязательно)" SecMain

    SectionIn RO

    SetOutPath "$INSTDIR"

    ; Копируем файлы
    File "..\docker-compose.yml"
    File "..\docker-compose.gpu.yml"
    File "..\uninstall.sh"
    File /r "..\scripts"

    ; Создаём .env файл если не существует
    IfFileExists "$INSTDIR\.env" env_exists
        ; Генерируем случайный ключ (упрощённо)
        FileOpen $0 "$INSTDIR\.env" w
        FileWrite $0 "WEBUI_SECRET_KEY=super-sistema-$(GetTickCount)$\r$\n"
        FileWrite $0 "WEBUI_PORT=${WEBUI_PORT}$\r$\n"
        FileWrite $0 "WEBUI_AUTH=false$\r$\n"
        FileWrite $0 "OLLAMA_KEEP_ALIVE=24h$\r$\n"
        FileWrite $0 "OLLAMA_NUM_PARALLEL=1$\r$\n"
        FileWrite $0 "OLLAMA_MAX_LOADED_MODELS=1$\r$\n"
        FileWrite $0 "DEFAULT_MODELS=llama3.2:3b$\r$\n"
        FileClose $0
    env_exists:

    ; Скачиваем образы и запускаем
    SetDetailsPrint both
    DetailPrint "Скачиваем Docker образы (может занять 5-10 минут)..."
    nsExec::ExecToLog 'docker compose pull'
    DetailPrint "Запускаем контейнеры..."
    nsExec::ExecToLog 'docker compose up -d'

    ; Создаём ярлык на рабочем столе
    CreateShortcut "$DESKTOP\Super Sistema.lnk" \
        "$SYSDIR\cmd.exe" \
        '/c start http://localhost:${WEBUI_PORT}' \
        "$INSTDIR\assets\icon.ico" 0 \
        SW_SHOWMINIMIZED "" "Открыть Super Sistema"

    ; Ярлык в меню Пуск
    CreateDirectory "$SMPROGRAMS\Super Sistema"
    CreateShortcut "$SMPROGRAMS\Super Sistema\Super Sistema.lnk" \
        "$SYSDIR\cmd.exe" \
        '/c start http://localhost:${WEBUI_PORT}' \
        "" 0 SW_SHOWMINIMIZED "" "Открыть Super Sistema"
    CreateShortcut "$SMPROGRAMS\Super Sistema\Удалить Super Sistema.lnk" \
        "$INSTDIR\uninstall.exe"

    ; Записываем путь установки в реестр
    WriteRegStr HKLM "Software\${PRODUCT_NAME}" "" $INSTDIR

    ; Добавляем в "Программы и компоненты"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayName"     "${PRODUCT_NAME}"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayIcon"     "$INSTDIR\assets\icon.ico"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "Publisher"       "${PRODUCT_PUBLISHER}"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "DisplayVersion"  "${PRODUCT_VERSION}"
    WriteRegStr   ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "URLInfoAbout"    "${PRODUCT_WEB_SITE}"
    WriteRegDWORD ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "NoModify"        1
    WriteRegDWORD ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" "NoRepair"        1

    ; Создаём удалятор
    WriteUninstaller "$INSTDIR\uninstall.exe"

SectionEnd

;=============================================================================
; Удалятор
;=============================================================================
Section Uninstall

    ; Останавливаем контейнеры
    SetOutPath "$INSTDIR"
    nsExec::ExecToLog 'docker compose down'

    MessageBox MB_ICONQUESTION|MB_YESNO \
        "Удалить также все данные (AI модели, история чатов)?$\r$\nЭто освободит несколько гигабайт на диске." \
        IDNO skip_volumes

    nsExec::ExecToLog 'docker volume rm super-sistema-ollama-data super-sistema-webui-data'

    skip_volumes:

    ; Удаляем файлы
    Delete "$INSTDIR\docker-compose.yml"
    Delete "$INSTDIR\docker-compose.gpu.yml"
    Delete "$INSTDIR\.env"
    Delete "$INSTDIR\uninstall.exe"
    RMDir /r "$INSTDIR\scripts"
    RMDir "$INSTDIR"

    ; Удаляем ярлыки
    Delete "$DESKTOP\Super Sistema.lnk"
    Delete "$SMPROGRAMS\Super Sistema\Super Sistema.lnk"
    Delete "$SMPROGRAMS\Super Sistema\Удалить Super Sistema.lnk"
    RMDir  "$SMPROGRAMS\Super Sistema"

    ; Чистим реестр
    DeleteRegKey ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}"
    DeleteRegKey HKLM "Software\${PRODUCT_NAME}"

    SetAutoClose true

SectionEnd

;=============================================================================
; GitHub Actions workflow для сборки .exe (сохраните как .github/workflows/build.yml)
;=============================================================================
; name: Build Windows Installer
; on:
;   push:
;     tags: ['v*']
; jobs:
;   build:
;     runs-on: windows-latest
;     steps:
;       - uses: actions/checkout@v4
;       - name: Install NSIS
;         run: choco install nsis -y
;       - name: Build installer
;         run: makensis installer/setup.nsi
;       - name: Upload to Release
;         uses: softprops/action-gh-release@v1
;         with:
;           files: installer/SuperSistema-Setup.exe
