Unicode true
!include "MUI2.nsh"
Name "咕咕提醒 · 原生版"
OutFile "..\dist\Gugu-Reminder-Native-0.2.0-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\GuguReminderNative"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64
!define MUI_ICON "..\src\desktop\icons\gugu.ico"
!define MUI_UNICON "..\src\desktop\icons\gugu.ico"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\GuguReminder.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
Function .onInit
 System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\GuguReminderNative") p.r0'
 ${If} $0 != 0
  System::Call 'kernel32::CloseHandle(p r0)'
  MessageBox MB_OK "请先从托盘退出咕咕提醒原生版，再安装。"
  Abort
 ${EndIf}
FunctionEnd
Section "安装"
 SetShellVarContext current
 SetOutPath "$INSTDIR"
 File "..\dist\native\GuguReminder.exe"
 SetOutPath "$INSTDIR\assets"
 File "..\dist\native\assets\*.webm"
 File "..\dist\native\assets\ffmpeg.exe"
 File "..\dist\native\assets\FFmpeg-LICENSE.txt"
 File "..\dist\native\assets\FFmpeg-README.txt"
 File "..\dist\native\assets\THIRD-PARTY-NOTICES.txt"
 File "..\dist\native\assets\*.ttf"
 File "..\dist\native\assets\OFL.txt"
 File "..\dist\native\assets\gugu.ico"
 WriteUninstaller "$INSTDIR\Uninstall.exe"
 CreateShortcut "$DESKTOP\咕咕提醒原生版.lnk" "$INSTDIR\GuguReminder.exe" "" "$INSTDIR\assets\gugu.ico"
 CreateShortcut "$SMPROGRAMS\咕咕提醒原生版.lnk" "$INSTDIR\GuguReminder.exe" "" "$INSTDIR\assets\gugu.ico"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "DisplayName" "咕咕提醒原生版"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "DisplayVersion" "0.2.0"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "UninstallString" '"$INSTDIR\Uninstall.exe"'
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "DisplayIcon" "$INSTDIR\GuguReminder.exe"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "InstallLocation" "$INSTDIR"
 WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "NoModify" 1
 WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative" "NoRepair" 1
SectionEnd
Section "Uninstall"
 SetShellVarContext current
 System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\GuguReminderNative") p.r0'
 ${If} $0 != 0
  System::Call 'kernel32::CloseHandle(p r0)'
  MessageBox MB_OK "请先从托盘退出咕咕提醒原生版，再卸载。"
  Abort
 ${EndIf}
 Delete "$DESKTOP\咕咕提醒原生版.lnk"
 Delete "$SMPROGRAMS\咕咕提醒原生版.lnk"
 Delete "$INSTDIR\assets\water.webm"
 Delete "$INSTDIR\assets\walk.webm"
 Delete "$INSTDIR\assets\eyes.webm"
 Delete "$INSTDIR\assets\ZCOOLKuaiLe-Regular.ttf"
 Delete "$INSTDIR\assets\OFL.txt"
 Delete "$INSTDIR\assets\gugu.ico"
 Delete "$INSTDIR\assets\ffmpeg.exe"
 Delete "$INSTDIR\assets\FFmpeg-LICENSE.txt"
 Delete "$INSTDIR\assets\FFmpeg-README.txt"
 Delete "$INSTDIR\assets\THIRD-PARTY-NOTICES.txt"
 Delete "$INSTDIR\GuguReminder.exe"
 Delete "$INSTDIR\Uninstall.exe"
 RMDir "$INSTDIR\assets"
 RMDir "$INSTDIR"
 DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\GuguReminderNative"
SectionEnd
