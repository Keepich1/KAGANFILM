; Установщик «Ордо» для Windows (NSIS 3). Собирается скриптом tools/build_windows.sh:
; скрипт, значок и файлы игры лежат в одной папке.
; Ставит игру в профиль пользователя (права администратора не нужны),
; создаёт ярлыки на рабочем столе и в «Пуске», регистрирует удаление.
Unicode true
!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.1.0"
!endif

Name "Ордо — срез стиля"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\Ordo"
InstallDirRegKey HKCU "Software\Ordo" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "Ордо ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1049 "ProductName" "Ордо"
VIAddVersionKey /LANG=1049 "FileDescription" "Установщик «Ордо» — срез стиля"
VIAddVersionKey /LANG=1049 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1049 "CompanyName" "KAGANFILM"
VIAddVersionKey /LANG=1049 "LegalCopyright" "KAGANFILM"

!define MUI_ICON "ordo.ico"
!define MUI_UNICON "ordo.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Ордо — срез стиля"
!define MUI_WELCOMEPAGE_TEXT "Лагерь кыпчаков на закате и столкновение двух отрядов.$\r$\n$\r$\nЭто первый этап игры: проверка стиля, света и анимаций. Экономики и других режимов пока нет.$\r$\n$\r$\nНужна видеокарта с поддержкой Vulkan или DirectX 12."
!define MUI_FINISHPAGE_RUN "$INSTDIR\Ordo.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить «Ордо»"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Section "Ордо"
  SetOutPath "$INSTDIR"
  File "Ordo.exe"
  File "Ordo.pck"
  File "ordo.ico"
  File "ПРОЧТИ.txt"
  WriteUninstaller "$INSTDIR\Удалить.exe"
  WriteRegStr HKCU "Software\Ordo" "InstallDir" "$INSTDIR"
  CreateDirectory "$SMPROGRAMS\Ордо"
  CreateShortcut "$SMPROGRAMS\Ордо\Ордо.lnk" "$INSTDIR\Ordo.exe" "" "$INSTDIR\ordo.ico"
  CreateShortcut "$SMPROGRAMS\Ордо\Удалить «Ордо».lnk" "$INSTDIR\Удалить.exe"
  CreateShortcut "$DESKTOP\Ордо.lnk" "$INSTDIR\Ordo.exe" "" "$INSTDIR\ordo.ico"
  !define UNINST "Software\Microsoft\Windows\CurrentVersion\Uninstall\Ordo"
  WriteRegStr HKCU "${UNINST}" "DisplayName" "Ордо — срез стиля"
  WriteRegStr HKCU "${UNINST}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST}" "Publisher" "KAGANFILM"
  WriteRegStr HKCU "${UNINST}" "DisplayIcon" "$INSTDIR\ordo.ico"
  WriteRegStr HKCU "${UNINST}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST}" "UninstallString" '"$INSTDIR\Удалить.exe"'
  WriteRegDWORD HKCU "${UNINST}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\Ordo.exe"
  Delete "$INSTDIR\Ordo.pck"
  Delete "$INSTDIR\ordo.ico"
  Delete "$INSTDIR\ПРОЧТИ.txt"
  Delete "$INSTDIR\Удалить.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\Ордо.lnk"
  Delete "$SMPROGRAMS\Ордо\Ордо.lnk"
  Delete "$SMPROGRAMS\Ордо\Удалить «Ордо».lnk"
  RMDir "$SMPROGRAMS\Ордо"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Ordo"
  DeleteRegKey HKCU "Software\Ordo"
SectionEnd
