@echo off
setlocal enabledelayedexpansion
title ESET Offline Reset Tool v0.2

:: =================================================================
:: ESET Offline Reset Management Tool - v0.2 (Base64 Method)
:: =================================================================

:: --- Configuration ---
set MOUNT_DIR=%SystemDrive%\WinRE_Mount
set PAYLOAD_FILENAME=Offline-Reset.cmd
set PAYLOAD_B64_TEMP=%TEMP%\payload.b64
set LOGFILE=%~dp0ESET_Reset_Tool.log
set PARENT_SCRIPT=%~f0
set "REG_HINT=HKLM\SOFTWARE\ESETReset"
set "LOG_PATH=%~dp0ESET_Reset_Tool.log"

:: Fast UAC Check using fsutil
>nul 2>&1 fsutil dirty query %systemdrive%
if errorlevel 1 (
    echo.
    echo  Requesting administrator privileges...
    if "%*"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList \"%*\" -Verb RunAs"
    )
    exit /b
)
:gotAdmin
pushd "%~dp0"

:: --disarm flag handler
if /I "%~1"=="--disarm" (
    echo [INFO]  --disarm flag detected >> "%LOGFILE%"
    echo  Disarm mode - Restoring defaults...
    set "NONINTERACTIVE=1"
    goto :disable_reset
)

:: --arm flag handler
if /I "%~1"=="--arm" (
    echo  Arm mode - Configuring reset...
    echo [INFO]  --arm flag detected >> "%LOGFILE%"
    set "NONINTERACTIVE=1"
    goto :enable_reset
)

echo. >> "%LOGFILE%"
echo ================= [%date% %time%] Script Started ================= >> "%LOGFILE%"

:: --- PRE-FLIGHT CHECKS ---
echo [INFO] Cleaning up any stale mounts... >> "%LOGFILE%"
dism /cleanup-wim >> "%LOGFILE%" 2>&1

echo [INFO] Checking for BitLocker... >> "%LOGFILE%"
manage-bde -status %SystemDrive% | find "Protection On" >nul
if not errorlevel 1 (
    echo.
    echo  ==== BITLOCKER WARNING ====
    echo.
    echo  BitLocker is ENABLED. You'll need your recovery key.
    echo  Get it at: https://account.microsoft.com/devices/recoverykey
    echo.
    pause
)

:menu
cls
echo  ===============================================================
echo                   ESET OFFLINE RESET TOOL
echo                         Version 0.2
echo  ===============================================================
echo.
echo  This tool configures Windows Recovery Environment to
echo  automatically reset ESET on the next system restart.
echo.
echo  [1] Arm automatic reset
echo  [2] Disarm automatic reset
echo  [3] Exit
echo.
choice /C 123 /N /M " Select: "
if errorlevel 3 goto :eof
if errorlevel 2 goto :disable_reset
if errorlevel 1 goto :enable_reset

:: =================================================================
:enable_reset
cls
echo [INFO] Arming reset process... >> "%LOGFILE%"
call :cleanup_mount

echo.
echo  Configuring automatic reset...
echo.
echo  - Extracting payload...
echo [INFO] Extracting payload from base64... >> "%LOGFILE%"
call :extract_payload
if errorlevel 1 (
    echo    FAILED - Check log file
    goto end_error
)

echo  - Mounting recovery image... be patient. Do not close window.
echo [INFO] Mounting WinRE image... >> "%LOGFILE%"
reagentc /mountre /path "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo    FAILED - Check log file
    goto end_error
)

echo  - Backing up files...
echo [INFO] Backing up original winpeshl.ini... >> "%LOGFILE%"
if exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini" (
    if not exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" (
        copy "%MOUNT_DIR%\Windows\System32\winpeshl.ini" "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" >nul
    )
)

echo  - Installing payload...
echo [INFO] Injecting payload script... >> "%LOGFILE%"
copy "%TEMP%\%PAYLOAD_FILENAME%" "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%" >> "%LOGFILE%" 2>&1

echo  - Recording log path...
echo [INFO] Recording log path in registry... >> "%LOGFILE%"
reg add "%REG_HINT%" /v "LogPath" /t REG_SZ /d "%LOG_PATH%" /f >> "%LOGFILE%" 2>&1

echo  - Configuring startup...
echo [INFO] Configuring WinRE startup... >> "%LOGFILE%"
echo [LaunchApps] > "%MOUNT_DIR%\Windows\System32\winpeshl.ini"
echo %%SystemRoot%%\System32\cmd.exe, /c %%SystemRoot%%\System32\%PAYLOAD_FILENAME% >> "%MOUNT_DIR%\Windows\System32\winpeshl.ini"

echo  - Saving changes...
echo [INFO] Committing changes to WinRE... >> "%LOGFILE%"
Dism /Commit-Image /MountDir:"%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to commit WinRE changes >> "%LOGFILE%"
    echo    FAILED - Files may be in use
    goto end_error
)

del "%TEMP%\%PAYLOAD_FILENAME%" >nul 2>&1

reagentc /boottore >> "%LOGFILE%" 2>&1
if errorlevel 1 ( 
    echo    WARNING - Could not set recovery boot
)

echo  - Creating cleanup task...
echo [INFO] Creating Run-Once Scheduled Task >> "%LOGFILE%"
schtasks /Create /TN "ESETResetDisarm" /TR "\"%~f0\" --disarm" /SC ONLOGON /RL HIGHEST /IT /RU "%USERNAME%" /F >nul 2>>"%LOGFILE%"

powershell -NoLogo -NoProfile -Command "$t = Get-ScheduledTask -TaskName 'ESETResetDisarm'; $t.Settings.DisallowStartIfOnBatteries = $false; $t.Settings.StopIfGoingOnBatteries = $false; Set-ScheduledTask -TaskName 'ESETResetDisarm' -TaskPath '\' -Settings $t.Settings" >nul 2>>"%LOGFILE%"
  
echo.
echo  ==== SUCCESS ====
echo.
echo  ESET reset configured. It will run on next restart.
echo.

if defined NONINTERACTIVE (
    echo [INFO] Auto-restart in 4 seconds... >> "%LOGFILE%"
    shutdown /r /t 4 /c "Restarting for ESET reset..."
    goto :eof
)

choice /C YN /M " Restart now? "
if errorlevel 2 goto :menu
if errorlevel 1 shutdown /r /t 4 /c "Restarting for ESET reset..."
goto :eof

:: =================================================================
:disable_reset
cls
echo.
echo  Disabling automatic reset...
echo.

echo [INFO] Disarming reset process... >> "%LOGFILE%"
if exist "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%" (
    echo  - Removing payload...
    echo [INFO] Removing payload script... >> "%LOGFILE%"
    del "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%" >nul 2>&1
)

if exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" (
    echo  - Restoring files...
    echo [INFO] Restoring original winpeshl.ini... >> "%LOGFILE%"
    copy /y "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" "%MOUNT_DIR%\Windows\System32\winpeshl.ini" >nul
    del "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" >nul
)

echo  - Cleaning registry...
echo [INFO] Removing script location from registry... >> "%LOGFILE%"
reg delete "%REG_HINT%" /f >> "%LOGFILE%" 2>&1

echo  - Removing tasks...
echo [INFO] Removing Scheduled Task... >> "%LOGFILE%"
schtasks /delete /tn "ESETResetDisarm" /f >nul 2>&1

echo  - Clearing recovery flag...
echo [INFO] Clear Winre on next boot flag... >> "%LOGFILE%"
reagentc /disable >> "%LOGFILE%" 2>&1
reagentc /enable >> "%LOGFILE%" 2>&1 

echo  - Unmounting image... be patient. Do not close window.
echo [INFO] Committing cleanup and unmounting WinRE... >> "%LOGFILE%"
reagentc /unmountre /path "%MOUNT_DIR%" /commit >> "%LOGFILE%" 2>&1
dism /cleanup-wim >> "%LOGFILE%" 2>&1
rd /s /q "%MOUNT_DIR%" 2>nul

echo.
echo  ==== SUCCESS ====
echo.
echo  Automatic reset disabled. System restored to normal.
echo.
goto end_success

:end_error
echo.
echo  Operation failed. Check ESET_Reset_Tool.log for details.
echo.
if defined NONINTERACTIVE exit /b 1
pause
goto :menu

:end_success
if defined NONINTERACTIVE exit /b 0
pause
goto :menu

:: =================================================================
:cleanup_mount
echo [INFO] Cleaning up mount directory... >> "%LOGFILE%"
if exist "%MOUNT_DIR%" dism /cleanup-wim >> "%LOGFILE%" 2>&1
dism /cleanup-wim >> "%LOGFILE%" 2>&1
mkdir "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
goto :eof

:: =================================================================
:extract_payload
echo [INFO] Creating base64 temp file... >> "%LOGFILE%"

:: BASE64_PAYLOAD_PLACEHOLDER - Build script will replace this line
echo -----BEGIN CERTIFICATE----- > "%PAYLOAD_B64_TEMP%"
echo QGVjaG8gb2ZmDQpzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo IEVTRVQgUmVnaXN0cnkgUmVzZXQgU2NyaXB0IGZvciBXaW5QRS9XaW5SRQ0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo byA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCndw >> "%PAYLOAD_B64_TEMP%"
echo ZXV0aWwgQ3JlYXRlQ29uc29sZSA+bnVsIDI+JjENCg0KOjogU2ltcGxlIGxvZ2dp >> "%PAYLOAD_B64_TEMP%"
echo bmcgc2V0dXAgLSBvbmx5IG5lZWQgdGVtcCBmaWxlDQpzZXQgVEVNUF9MT0dGSUxF >> "%PAYLOAD_B64_TEMP%"
echo PVg6XGVzZXRfcmVzZXQubG9nDQpzZXQgTUFJTl9MT0dGSUxFPQ0Kc2V0IE5PTklO >> "%PAYLOAD_B64_TEMP%"
echo VEVSQUNUSVZFPTANCg0KOjogQ2FwdHVyZSBXaW5QRSBzaGVsbCBsb2cNCmlmIGV4 >> "%PAYLOAD_B64_TEMP%"
echo aXN0ICJYOlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmxvZyIgKA0KICAgIGVj >> "%PAYLOAD_B64_TEMP%"
echo aG8gWyVkYXRlJSAldGltZSVdID09PSBXaW5QRSBTaGVsbCBMb2cgQ29udGVudHMg >> "%PAYLOAD_B64_TEMP%"
echo PT09PT4+IiVURU1QX0xPR0ZJTEUlIg0KICAgIHR5cGUgIlg6XFdpbmRvd3NcU3lz >> "%PAYLOAD_B64_TEMP%"
echo dGVtMzJcd2lucGVzaGwubG9nIj4+IiVURU1QX0xPR0ZJTEUlIiAyPm51bA0KICAg >> "%PAYLOAD_B64_TEMP%"
echo IGVjaG8gWyVkYXRlJSAldGltZSVdID09PSBFbmQgV2luUEUgU2hlbGwgTG9nID09 >> "%PAYLOAD_B64_TEMP%"
echo PT4+IiVURU1QX0xPR0ZJTEUlIg0KKQ0KDQpjYWxsIDpMb2cgIj09PSBXaW5SRSBT >> "%PAYLOAD_B64_TEMP%"
echo Y3JpcHQgU2Vzc2lvbiBTdGFydGVkID09PSINCmNhbGwgOkxvZyAiRVNFVCBSZWdp >> "%PAYLOAD_B64_TEMP%"
echo c3RyeSBSZXNldCBTY3JpcHQgZm9yIFdpblBFL1dpblJFIg0KDQo6OiBJbml0aWFs >> "%PAYLOAD_B64_TEMP%"
echo aXplIHZhcmlhYmxlcw0Kc2V0IFdJTkRSSVZFPQ0Kc2V0IFdJTkRJUj0NCg0KOjog >> "%PAYLOAD_B64_TEMP%"
echo U2NhbiBmb3IgV2luZG93cyBpbnN0YWxsYXRpb24NCmNhbGwgOkxvZyAiU2Nhbm5p >> "%PAYLOAD_B64_TEMP%"
echo bmcgZm9yIFdpbmRvd3MgaW5zdGFsbGF0aW9uLi4uIg0KDQpmb3IgJSVEIGluIChD >> "%PAYLOAD_B64_TEMP%"
echo IEQgRSBGIEcgSCBJIEogSyBMIE0gTiBPIFAgUSBSIFMgVCBVIFYgVyBYIFkgWikg >> "%PAYLOAD_B64_TEMP%"
echo ZG8gKA0KICAgIGlmIGV4aXN0ICIlJUQ6XFdpbmRvd3NcU3lzdGVtMzJcQ29uZmln >> "%PAYLOAD_B64_TEMP%"
echo XFNPRlRXQVJFIiAoDQogICAgICAgIHNldCBXSU5EUklWRT0lJUQ6DQogICAgICAg >> "%PAYLOAD_B64_TEMP%"
echo IHNldCBXSU5ESVI9JSVEOlxXaW5kb3dzDQogICAgICAgIGNhbGwgOkxvZyAiRm91 >> "%PAYLOAD_B64_TEMP%"
echo bmQgV2luZG93cyBpbnN0YWxsYXRpb24gb246ICUlRDoiDQogICAgICAgIGdvdG8g >> "%PAYLOAD_B64_TEMP%"
echo OkZvdW5kSW5zdGFsbGF0aW9uDQogICAgKQ0KKQ0KDQpjYWxsIDpMb2cgIltGQVRB >> "%PAYLOAD_B64_TEMP%"
echo TF0gTm8gV2luZG93cyBpbnN0YWxsYXRpb24gZm91bmQiDQpjYWxsIDpOb1dpbmRv >> "%PAYLOAD_B64_TEMP%"
echo d3NXYXJuaW5nICJObyBXaW5kb3dzIGluc3RhbGxhdGlvbiBmb3VuZCBvbiBhbnkg >> "%PAYLOAD_B64_TEMP%"
echo ZHJpdmUiDQpnb3RvIDpFbmRTY3JpcHQNCg0KOkZvdW5kSW5zdGFsbGF0aW9uDQpj >> "%PAYLOAD_B64_TEMP%"
echo YWxsIDpMb2cgIlNlbGVjdGVkIFdpbmRvd3MgaW5zdGFsbGF0aW9uOiAlV0lORElS >> "%PAYLOAD_B64_TEMP%"
echo JSINCg0KOjogRGVsZXRlIEVTRVQgbGljZW5zZSBmaWxlDQpjYWxsIDpMb2cgIkRl >> "%PAYLOAD_B64_TEMP%"
echo bGV0aW5nIEVTRVQgbGljZW5zZSBmaWxlLi4uIg0Kc2V0IExJQ0VOU0VQQVRIPSVX >> "%PAYLOAD_B64_TEMP%"
echo SU5EUklWRSVcUHJvZ3JhbURhdGFcRVNFVFxFU0VUIFNlY3VyaXR5XExpY2Vuc2Vc >> "%PAYLOAD_B64_TEMP%"
echo bGljZW5zZS5sZg0KaWYgZXhpc3QgIiVMSUNFTlNFUEFUSCUiICgNCiAgICBhdHRy >> "%PAYLOAD_B64_TEMP%"
echo aWIgLXIgLWggLXMgIiVMSUNFTlNFUEFUSCUiID5udWwgMj4mMQ0KICAgIGRlbCAv >> "%PAYLOAD_B64_TEMP%"
echo ZiAiJUxJQ0VOU0VQQVRIJSIgPm51bCAyPiYxDQogICAgaWYgZXhpc3QgIiVMSUNF >> "%PAYLOAD_B64_TEMP%"
echo TlNFUEFUSCUiICgNCiAgICAgICAgY2FsbCA6TG9nICJbV0FSTl0gRmFpbGVkIHRv >> "%PAYLOAD_B64_TEMP%"
echo IGRlbGV0ZSBsaWNlbnNlIGZpbGUiDQogICAgKSBlbHNlICgNCiAgICAgICAgY2Fs >> "%PAYLOAD_B64_TEMP%"
echo bCA6TG9nICJMaWNlbnNlIGZpbGUgZGVsZXRlZCBzdWNjZXNzZnVsbHkiDQogICAg >> "%PAYLOAD_B64_TEMP%"
echo KQ0KKSBlbHNlICgNCiAgICBjYWxsIDpMb2cgIkxpY2Vuc2UgZmlsZSBub3QgZm91 >> "%PAYLOAD_B64_TEMP%"
echo bmQiDQopDQoNCjo6IExvYWQgdGhlIFNPRlRXQVJFIGhpdmUNCmNhbGwgOkxvZyAi >> "%PAYLOAD_B64_TEMP%"
echo TG9hZGluZyBvZmZsaW5lIFNPRlRXQVJFIGhpdmUuLi4iDQpyZWcgbG9hZCBIS0xN >> "%PAYLOAD_B64_TEMP%"
echo XE9GRkxJTkVfU09GVFdBUkUgIiVXSU5ESVIlXFN5c3RlbTMyXENvbmZpZ1xTT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICAgIGNhbGwgOkZh >> "%PAYLOAD_B64_TEMP%"
echo dGFsRXJyb3IgIkZhaWxlZCB0byBsb2FkIFNPRlRXQVJFIGhpdmUiDQopDQpjYWxs >> "%PAYLOAD_B64_TEMP%"
echo IDpMb2cgIlNPRlRXQVJFIGhpdmUgbG9hZGVkIHN1Y2Nlc3NmdWxseSINCg0KOjog >> "%PAYLOAD_B64_TEMP%"
echo U0lNUExJRklFRDogR2V0IG1haW4gbG9nIHBhdGggYW5kIGRvIGluaXRpYWwgZHVt >> "%PAYLOAD_B64_TEMP%"
echo cA0KY2FsbCA6TG9nICJSZXRyaWV2aW5nIGxvZyBwYXRoIGZyb20gcmVnaXN0cnku >> "%PAYLOAD_B64_TEMP%"
echo Li4iDQpjYWxsIDpTZXR1cE1haW5Mb2dnaW5nDQoNCjo6IFBlcmZvcm0gYWxsIHJl >> "%PAYLOAD_B64_TEMP%"
echo Z2lzdHJ5IG9wZXJhdGlvbnMNCmNhbGwgOkxvZyAiU3RhcnRpbmcgRVNFVCByZWdp >> "%PAYLOAD_B64_TEMP%"
echo c3RyeSBtb2RpZmljYXRpb25zLi4uIg0KDQo6OiBDb3VudGVyIGZvciBvcGVyYXRp >> "%PAYLOAD_B64_TEMP%"
echo b25zDQpzZXQgT1BTPTANCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9T >> "%PAYLOAD_B64_TEMP%"
echo T0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmln >> "%PAYLOAD_B64_TEMP%"
echo XHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxDaGVjayIgL3YgIkNmZ1Nl >> "%PAYLOAD_B64_TEMP%"
echo cU51bWJlckVzZXRBY2NHbG9iYWwiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9y >> "%PAYLOAD_B64_TEMP%"
echo bGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9G >> "%PAYLOAD_B64_TEMP%"
echo RkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9u >> "%PAYLOAD_B64_TEMP%"
echo XENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cQ2hlY2siIC92 >> "%PAYLOAD_B64_TEMP%"
echo ICJETlNUaW1lclNlYyIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo IHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBs >> "%PAYLOAD_B64_TEMP%"
echo dWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxDaGVjayIgL2YgPm51bCAyPiYx >> "%PAYLOAD_B64_TEMP%"
echo DQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAw >> "%PAYLOAD_B64_TEMP%"
echo MDA2XHNldHRpbmdzXEVrcm5cRWNwIiAvdiAiU2VhdElEIiAvZiA+bnVsIDI+JjEN >> "%PAYLOAD_B64_TEMP%"
echo CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRl >> "%PAYLOAD_B64_TEMP%"
echo bGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxD >> "%PAYLOAD_B64_TEMP%"
echo dXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xF >> "%PAYLOAD_B64_TEMP%"
echo a3JuXEVjcCIgL3YgIkNvbXB1dGVyTmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3Qg >> "%PAYLOAD_B64_TEMP%"
echo ZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhL >> "%PAYLOAD_B64_TEMP%"
echo TE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZl >> "%PAYLOAD_B64_TEMP%"
echo cnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxFY3Ai >> "%PAYLOAD_B64_TEMP%"
echo IC92ICJUb2tlbiIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdp >> "%PAYLOAD_B64_TEMP%"
echo bnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxFY3AiIC9mID5udWwgMj4mMQ0KDQpS >> "%PAYLOAD_B64_TEMP%"
echo ZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBT >> "%PAYLOAD_B64_TEMP%"
echo ZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxz >> "%PAYLOAD_B64_TEMP%"
echo ZXR0aW5nc1xFa3JuXEluZm8iIC92ICJMYXN0SHdmIiAvZiA+bnVsIDI+JjENCmlm >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0 >> "%PAYLOAD_B64_TEMP%"
echo ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJy >> "%PAYLOAD_B64_TEMP%"
echo ZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3Ju >> "%PAYLOAD_B64_TEMP%"
echo XEluZm8iIC92ICJBY3RpdmF0aW9uU3RhdGUiIC9mID5udWwgMj4mMQ0KaWYgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cSW5m >> "%PAYLOAD_B64_TEMP%"
echo byIgL3YgIkFjdGl2YXRpb25UeXBlIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv >> "%PAYLOAD_B64_TEMP%"
echo cmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxP >> "%PAYLOAD_B64_TEMP%"
echo RkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lv >> "%PAYLOAD_B64_TEMP%"
echo blxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEluZm8iIC92 >> "%PAYLOAD_B64_TEMP%"
echo ICJMYXN0QWN0aXZhdGlvbkRhdGUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9y >> "%PAYLOAD_B64_TEMP%"
echo bGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENv >> "%PAYLOAD_B64_TEMP%"
echo bmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cSW5mbyIgL2YgPm51 >> "%PAYLOAD_B64_TEMP%"
echo bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5z >> "%PAYLOAD_B64_TEMP%"
echo XDAxMDAwMjAwXHNldHRpbmdzXHN0UHJvdG9jb2xGaWx0ZXJpbmdcc3RBcHBTc2wi >> "%PAYLOAD_B64_TEMP%"
echo IC92ICJ1Um9vdENyZWF0ZVRpbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9y >> "%PAYLOAD_B64_TEMP%"
echo bGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENv >> "%PAYLOAD_B64_TEMP%"
echo bmZpZ1xwbHVnaW5zXDAxMDAwMjAwXHNldHRpbmdzXHN0UHJvdG9jb2xGaWx0ZXJp >> "%PAYLOAD_B64_TEMP%"
echo bmdcc3RBcHBTc2wiIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtM >> "%PAYLOAD_B64_TEMP%"
echo TVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVy >> "%PAYLOAD_B64_TEMP%"
echo c2lvblxQbHVnaW5zXDAxMDAwNDAwXENvbmZpZ0JhY2t1cCIgL3YgIlVzZXJuYW1l >> "%PAYLOAD_B64_TEMP%"
echo IiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9 >> "%PAYLOAD_B64_TEMP%"
echo MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxQbHVnaW5zXDAxMDAwNDAwXENv >> "%PAYLOAD_B64_TEMP%"
echo bmZpZ0JhY2t1cCIgL3YgIlBhc3N3b3JkIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBl >> "%PAYLOAD_B64_TEMP%"
echo cnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtM >> "%PAYLOAD_B64_TEMP%"
echo TVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVy >> "%PAYLOAD_B64_TEMP%"
echo c2lvblxQbHVnaW5zXDAxMDAwNDAwXENvbmZpZ0JhY2t1cCIgL3YgIkxlZ2FjeVVz >> "%PAYLOAD_B64_TEMP%"
echo ZXJuYW1lIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9h >> "%PAYLOAD_B64_TEMP%"
echo IE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJF >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxQbHVnaW5zXDAxMDAw >> "%PAYLOAD_B64_TEMP%"
echo NDAwXENvbmZpZ0JhY2t1cCIgL3YgIkxlZ2FjeVBhc3N3b3JkIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxD >> "%PAYLOAD_B64_TEMP%"
echo dXJyZW50VmVyc2lvblxQbHVnaW5zXDAxMDAwNDAwXENvbmZpZ0JhY2t1cCIgL2Yg >> "%PAYLOAD_B64_TEMP%"
echo Pm51bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVn >> "%PAYLOAD_B64_TEMP%"
echo aW5zXDAxMDAwNDAwXHNldHRpbmdzIiAvdiAiUGFzc3dvcmQiIC9mID5udWwgMj4m >> "%PAYLOAD_B64_TEMP%"
echo MQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUg >> "%PAYLOAD_B64_TEMP%"
echo ZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5 >> "%PAYLOAD_B64_TEMP%"
echo XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwNDAwXHNldHRpbmdz >> "%PAYLOAD_B64_TEMP%"
echo IiAvdiAiVXNlcm5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwg >> "%PAYLOAD_B64_TEMP%"
echo MSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJTkVfU09G >> "%PAYLOAD_B64_TEMP%"
echo VFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xw >> "%PAYLOAD_B64_TEMP%"
echo bHVnaW5zXDAxMDAwNDAwXHNldHRpbmdzIiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4 >> "%PAYLOAD_B64_TEMP%"
echo ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJp >> "%PAYLOAD_B64_TEMP%"
echo dHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDA2MDBcc2V0dGlu >> "%PAYLOAD_B64_TEMP%"
echo Z3NcRGlzdFBhY2thZ2VcQXBwU2V0dGluZ3MiIC92ICJBY3RPcHRpb25zIiAvZiA+ >> "%PAYLOAD_B64_TEMP%"
echo bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpS >> "%PAYLOAD_B64_TEMP%"
echo ZWcuZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1 >> "%PAYLOAD_B64_TEMP%"
echo cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDYwMFxzZXR0 >> "%PAYLOAD_B64_TEMP%"
echo aW5nc1xEaXN0UGFja2FnZVxBcHBTZXR0aW5ncyIgL2YgPm51bCAyPiYxDQoNClJl >> "%PAYLOAD_B64_TEMP%"
echo Zy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNl >> "%PAYLOAD_B64_TEMP%"
echo Y3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNl >> "%PAYLOAD_B64_TEMP%"
echo dHRpbmdzXEVrcm5cSW5mb1xMYXN0SHdJbmZvIiAvdiAiQ29tcHV0ZXJOYW1lIiAv >> "%PAYLOAD_B64_TEMP%"
echo ZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0K >> "%PAYLOAD_B64_TEMP%"
echo DQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNF >> "%PAYLOAD_B64_TEMP%"
echo VCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAw >> "%PAYLOAD_B64_TEMP%"
echo NlxzZXR0aW5nc1xFa3JuXEluZm9cTGFzdEh3SW5mbyIgL3YgIlZlcnNpb24iIC9m >> "%PAYLOAD_B64_TEMP%"
echo ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoN >> "%PAYLOAD_B64_TEMP%"
echo ClJlZy5leGUgYWRkICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNl >> "%PAYLOAD_B64_TEMP%"
echo Y3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNl >> "%PAYLOAD_B64_TEMP%"
echo dHRpbmdzXEVrcm5cSW5mb1xMYXN0SHdJbmZvIiAvZiA+bnVsIDI+JjENCg0KUmVn >> "%PAYLOAD_B64_TEMP%"
echo LmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2Vj >> "%PAYLOAD_B64_TEMP%"
echo dXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIkVkaXRpb25OYW1lIiAvZiA+ >> "%PAYLOAD_B64_TEMP%"
echo bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpS >> "%PAYLOAD_B64_TEMP%"
echo ZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBT >> "%PAYLOAD_B64_TEMP%"
echo ZWN1cml0eVxDdXJyZW50VmVyc2lvblxJbmZvIiAvdiAiRnVsbFByb2R1Y3ROYW1l >> "%PAYLOAD_B64_TEMP%"
echo IiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9 >> "%PAYLOAD_B64_TEMP%"
echo MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJbmZvIiAvdiAiSW5zdGFsbGVk >> "%PAYLOAD_B64_TEMP%"
echo QnlFUkEiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2Eg >> "%PAYLOAD_B64_TEMP%"
echo T1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJBY3Rp >> "%PAYLOAD_B64_TEMP%"
echo dmVGZWF0dXJlcyIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3Yg >> "%PAYLOAD_B64_TEMP%"
echo IlVuaXF1ZUlkIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0 >> "%PAYLOAD_B64_TEMP%"
echo IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRX >> "%PAYLOAD_B64_TEMP%"
echo QVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJbmZvIiAvdiAi >> "%PAYLOAD_B64_TEMP%"
echo V2ViQWN0aXZhdGlvblN0YXRlIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxl >> "%PAYLOAD_B64_TEMP%"
echo dmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZM >> "%PAYLOAD_B64_TEMP%"
echo SU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJ >> "%PAYLOAD_B64_TEMP%"
echo bmZvIiAvdiAiV2ViU2VhdElkIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxl >> "%PAYLOAD_B64_TEMP%"
echo dmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZM >> "%PAYLOAD_B64_TEMP%"
echo SU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJ >> "%PAYLOAD_B64_TEMP%"
echo bmZvIiAvdiAiV2ViQ2xpZW50Q29tcHV0ZXJOYW1lIiAvZiA+bnVsIDI+JjENCmlm >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0 >> "%PAYLOAD_B64_TEMP%"
echo ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJy >> "%PAYLOAD_B64_TEMP%"
echo ZW50VmVyc2lvblxJbmZvIiAvdiAiV2ViTGljZW5zZVB1YmxpY0lkIiAvZiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1 >> "%PAYLOAD_B64_TEMP%"
echo cml0eVxDdXJyZW50VmVyc2lvblxJbmZvIiAvdiAiTGFzdEFjdGl2YXRpb25SZXN1 >> "%PAYLOAD_B64_TEMP%"
echo bHQiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BT >> "%PAYLOAD_B64_TEMP%"
echo Kz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC9mID5udWwgMj4mMQ0K >> "%PAYLOAD_B64_TEMP%"
echo DQpjYWxsIDpMb2cgIlJlZ2lzdHJ5IG1vZGlmaWNhdGlvbnMgY29tcGxldGUgLSBT >> "%PAYLOAD_B64_TEMP%"
echo dWNjZXNzZnVsbHkgZGVsZXRlZCAlT1BTJSB2YWx1ZXMiDQoNCjo6IFVubG9hZCB0 >> "%PAYLOAD_B64_TEMP%"
echo aGUgaGl2ZQ0KY2FsbCA6TG9nICJVbmxvYWRpbmcgU09GVFdBUkUgaGl2ZS4uLiIN >> "%PAYLOAD_B64_TEMP%"
echo CnJlZyB1bmxvYWQgSEtMTVxPRkZMSU5FX1NPRlRXQVJFID5udWwgMj4mMQ0KaWYg >> "%PAYLOAD_B64_TEMP%"
echo ZXJyb3JsZXZlbCAxICgNCiAgICBjYWxsIDpMb2cgIltXQVJOXSBGYWlsZWQgdG8g >> "%PAYLOAD_B64_TEMP%"
echo dW5sb2FkIGhpdmUgb24gZmlyc3QgYXR0ZW1wdCwgcmV0cnlpbmcuLi4iDQogICAg >> "%PAYLOAD_B64_TEMP%"
echo ZWNobyBXU2NyaXB0LlNsZWVwIDMwMDAgPiIlVEVNUCVcczMudmJzIg0KICAgIGNz >> "%PAYLOAD_B64_TEMP%"
echo Y3JpcHQgLy9ub2xvZ28gIiVURU1QJVxzMy52YnMiDQogICAgcmVnIHVubG9hZCBI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkUgPm51bCAyPiYxDQogICAgaWYgZXJyb3JsZXZl >> "%PAYLOAD_B64_TEMP%"
echo bCAxICgNCiAgICAgICAgY2FsbCA6TG9nICJbRVJST1JdIEZhaWxlZCB0byB1bmxv >> "%PAYLOAD_B64_TEMP%"
echo YWQgaGl2ZSBhZnRlciByZXRyeSAtIHdpbGwgcmVtYWluIGxvYWRlZCB1bnRpbCBy >> "%PAYLOAD_B64_TEMP%"
echo ZXN0YXJ0Ig0KICAgICkgZWxzZSAoDQogICAgICAgIGNhbGwgOkxvZyAiSGl2ZSB1 >> "%PAYLOAD_B64_TEMP%"
echo bmxvYWRlZCBzdWNjZXNzZnVsbHkgb24gcmV0cnkiDQogICAgKQ0KKSBlbHNlICgN >> "%PAYLOAD_B64_TEMP%"
echo CiAgICBjYWxsIDpMb2cgIkhpdmUgdW5sb2FkZWQgc3VjY2Vzc2Z1bGx5Ig0KKQ0K >> "%PAYLOAD_B64_TEMP%"
echo DQpjYWxsIDpMb2cgIlNVQ0NFU1M6IEVTRVQtUmVzZXQgY29tcGxldGUiDQpjYWxs >> "%PAYLOAD_B64_TEMP%"
echo IDpMb2cgIlRhcmdldCBzeXN0ZW06ICVXSU5ESVIlIg0KY2FsbCA6TG9nICJSZWdp >> "%PAYLOAD_B64_TEMP%"
echo c3RyeSB2YWx1ZXMgZGVsZXRlZDogJU9QUyUiDQpjYWxsIDpMb2cgIk5PVEU6IEVT >> "%PAYLOAD_B64_TEMP%"
echo RVQgd2lsbCBuZWVkIHRvIGJlIHJlYWN0aXZhdGVkIHdoZW4gV2luZG93cyBib290 >> "%PAYLOAD_B64_TEMP%"
echo cyINCg0KOjogQ3JlYXRlIHRoZSAxLXNlY29uZCBzbGVlcCB1dGlsaXR5DQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo IFdTY3JpcHQuU2xlZXAgMTAwMCA+IiVURU1QJVxzLnZicyINCg0KZWNoby4NCmVj >> "%PAYLOAD_B64_TEMP%"
echo aG8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0N >> "%PAYLOAD_B64_TEMP%"
echo CmVjaG8gICAgICAgICAgRVNFVCBSRVNFVCBDT01QTEVURUQNCmVjaG8gPT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCmVjaG8uDQpl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIFRhcmdldCBTeXN0ZW06ICVXSU5ESVIlDQplY2hvIFJlZ2lzdHJ5IFZhbHVl >> "%PAYLOAD_B64_TEMP%"
echo cyBEZWxldGVkOiAlT1BTJQ0KZWNoby4NCmVjaG8gRVNFVCB3aWxsIG5lZWQgdG8g >> "%PAYLOAD_B64_TEMP%"
echo YmUgcmVhY3RpdmF0ZWQgd2hlbiBXaW5kb3dzIGJvb3RzLg0KZWNoby4NCmVjaG8g >> "%PAYLOAD_B64_TEMP%"
echo UmVib290aW5nIGluIDcgc2Vjb25kcy4uLg0KDQo6OiBTaWxlbnQgY291bnRkb3du >> "%PAYLOAD_B64_TEMP%"
echo DQpmb3IgL0wgJSVpIGluICg3LC0xLDEpIGRvICgNCiAgICBjc2NyaXB0IC8vbm9s >> "%PAYLOAD_B64_TEMP%"
echo b2dvICIlVEVNUCVccy52YnMiDQopDQoNCmVjaG8uDQplY2hvIFJlYm9vdGluZyBu >> "%PAYLOAD_B64_TEMP%"
echo b3cuLi4NCmNhbGwgOkxvZyAiSW5pdGlhdGluZyBzeXN0ZW0gcmVib290Li4uIg0K >> "%PAYLOAD_B64_TEMP%"
echo DQp3cGV1dGlsIHJlYm9vdA0KZ290byA6RW5kU2NyaXB0DQoNCjo6IFNJTVBMSUZJ >> "%PAYLOAD_B64_TEMP%"
echo RUQgRlVOQ1RJT05TDQoNCjpMb2cNCnNldCAibG9ndGV4dD0lKiINCnNldCAibG9n >> "%PAYLOAD_B64_TEMP%"
echo dGV4dD0hbG9ndGV4dDoiPSEiDQplY2hvICFsb2d0ZXh0IQ0KaWYgZGVmaW5lZCBN >> "%PAYLOAD_B64_TEMP%"
echo QUlOX0xPR0ZJTEUgKA0KICAgIGVjaG8gWyVkYXRlJSAldGltZSVdICFsb2d0ZXh0 >> "%PAYLOAD_B64_TEMP%"
echo IT4+IiVNQUlOX0xPR0ZJTEUlIiAyPm51bA0KKSBlbHNlICgNCiAgICBlY2hvIFsl >> "%PAYLOAD_B64_TEMP%"
echo ZGF0ZSUgJXRpbWUlXSAhbG9ndGV4dCE+PiIlVEVNUF9MT0dGSUxFJSINCikNCmdv >> "%PAYLOAD_B64_TEMP%"
echo dG8gOmVvZg0KDQo6U2V0dXBNYWluTG9nZ2luZyANCjo6IEdldCBsb2cgcGF0aCBm >> "%PAYLOAD_B64_TEMP%"
echo cm9tIHJlZ2lzdHJ5IGFuZCBzZXQgdXAgbWFpbiBsb2cgZmlsZQ0Kc2V0ICJMT0df >> "%PAYLOAD_B64_TEMP%"
echo UEFUSD0iDQpmb3IgL2YgInRva2Vucz0yLCoiICUlQSBpbiAoJ3JlZyBxdWVyeSAi >> "%PAYLOAD_B64_TEMP%"
echo SEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRSZXNldCIgL3YgTG9nUGF0aCAyXj5u >> "%PAYLOAD_B64_TEMP%"
echo dWwgXnwgZmluZCAiUkVHX1NaIicpIGRvIHNldCAiTE9HX1BBVEg9JSVCIg0KDQpp >> "%PAYLOAD_B64_TEMP%"
echo ZiBkZWZpbmVkIExPR19QQVRIICgNCiAgICBjYWxsIDpMb2cgIkxvZyBwYXRoIGZv >> "%PAYLOAD_B64_TEMP%"
echo dW5kOiAlTE9HX1BBVEglIg0KICAgIA0KICAgIDo6IFBhdGggbWFwcGluZyAtIHJl >> "%PAYLOAD_B64_TEMP%"
echo cGxhY2UgQzogd2l0aCBkZXRlY3RlZCBkcml2ZQ0KICAgIHNldCAiTUFJTl9MT0dG >> "%PAYLOAD_B64_TEMP%"
echo SUxFPSVXSU5EUklWRSUlTE9HX1BBVEg6fjIlIg0KICAgIA0KICAgIGNhbGwgOkxv >> "%PAYLOAD_B64_TEMP%"
echo ZyAiTG9nIE1hcHBlZCB0byBXaW5SRSBwYXRoOiAhTUFJTl9MT0dGSUxFISINCiAg >> "%PAYLOAD_B64_TEMP%"
echo ICANCiAgICA6OiBEbyBpbml0aWFsIGR1bXANCiAgICBjYWxsIDpEdW1wVGVtcExv >> "%PAYLOAD_B64_TEMP%"
echo Zw0KICAgIGNhbGwgOkxvZyAiQ29udGludWVkIGZyb20gdGVtcCBsb2ciDQopIGVs >> "%PAYLOAD_B64_TEMP%"
echo c2UgKA0KICAgIGNhbGwgOkxvZyAiW1dBUk5dIExvZyBwYXRoIG5vdCBmb3VuZCBp >> "%PAYLOAD_B64_TEMP%"
echo biByZWdpc3RyeSwgY29udGludWluZyB3aXRoIHRlbXAgbG9nIG9ubHkiDQopDQpn >> "%PAYLOAD_B64_TEMP%"
echo b3RvIDplb2YNCg0KOkR1bXBUZW1wTG9nDQo6OiBEdW1wIHRlbXAgbG9nIHRvIG1h >> "%PAYLOAD_B64_TEMP%"
echo aW4gbG9nIGlmIHdlIGhhdmUgb25lDQppZiBkZWZpbmVkIE1BSU5fTE9HRklMRSAo >> "%PAYLOAD_B64_TEMP%"
echo DQogICAgaWYgZXhpc3QgIiVURU1QX0xPR0ZJTEUlIiAoDQogICAgICAgIGVjaG8g >> "%PAYLOAD_B64_TEMP%"
echo WyVkYXRlJSAldGltZSVdID09PSBEdW1waW5nIHRlbXAgbG9nIGNvbnRlbnRzID09 >> "%PAYLOAD_B64_TEMP%"
echo PT4+IiVNQUlOX0xPR0ZJTEUlIiAyPm51bA0KICAgICAgICB0eXBlICIlVEVNUF9M >> "%PAYLOAD_B64_TEMP%"
echo T0dGSUxFJSI+PiIlTUFJTl9MT0dGSUxFJSIgMj5udWwNCiAgICAgICAgZWNobyBb >> "%PAYLOAD_B64_TEMP%"
echo JWRhdGUlICV0aW1lJV0gPT09IEVuZCB0ZW1wIGxvZyBkdW1wID09PT4+IiVNQUlO >> "%PAYLOAD_B64_TEMP%"
echo X0xPR0ZJTEUlIiAyPm51bA0KICAgICkNCikNCmdvdG8gOmVvZg0KDQo6RmF0YWxF >> "%PAYLOAD_B64_TEMP%"
echo cnJvcg0KZWNoby4NCmNhbGwgOkxvZyAiW0ZBVEFMXSAlKiINCmVjaG8uDQppZiAi >> "%PAYLOAD_B64_TEMP%"
echo JU5PTklOVEVSQUNUSVZFJSI9PSIwIiAoDQogICAgZWNobyBBbiB1bnJlY292ZXJh >> "%PAYLOAD_B64_TEMP%"
echo YmxlIGVycm9yIG9jY3VycmVkLiBQbGVhc2UgY2hlY2sgdGhlIGxvZyBmaWxlIGZv >> "%PAYLOAD_B64_TEMP%"
echo ciBkZXRhaWxzLg0KICAgIHBhdXNlDQopDQpnb3RvIDpFbmRTY3JpcHQNCg0KOk5v >> "%PAYLOAD_B64_TEMP%"
echo V2luZG93c1dhcm5pbmcNCkBlY2hvIG9mZg0Kc2V0bG9jYWwgRW5hYmxlRXh0ZW5z >> "%PAYLOAD_B64_TEMP%"
echo aW9ucw0KDQo6OiBDcmVhdGUgdGhlIDEtc2Vjb25kIHNsZWVwIHV0aWxpdHkNCmVj >> "%PAYLOAD_B64_TEMP%"
echo aG8gV1NjcmlwdC5TbGVlcCAxMDAwID4iJVRFTVAlXHMudmJzIg0KDQpjbHMNCmNv >> "%PAYLOAD_B64_TEMP%"
echo bG9yIDRGDQplY2hvLg0KZWNobyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PQ0KZWNobyBXQVJOSU5HOiBXSU5ET1dTIElOU1RBTExB >> "%PAYLOAD_B64_TEMP%"
echo VElPTiBOT1QgREVURUNURUQNCmVjaG8gPT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT0NCmVjaG8uDQplY2hvICUqDQplY2hvLg0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo byBIZXkgbWFuLiBIb3cgZGlkIHlvdSBwdWxsIGhpcyBvZmY/IFRoaXMgc2NyaXB0 >> "%PAYLOAD_B64_TEMP%"
echo IHJlcXVpcmVzIFdJTkRPV1MgdG8gYmUgaW5zdGFsbGVkLg0KZWNoby4NCg0KOjog >> "%PAYLOAD_B64_TEMP%"
echo Q291bnRkb3duIGJ5IHByaW50aW5nIGEgbmV3IGxpbmUgZWFjaCBzZWNvbmQNCmZv >> "%PAYLOAD_B64_TEMP%"
echo ciAvTCAlJWkgaW4gKDE1LC0xLDEpIGRvICgNCiAgICBlY2hvIFdJTkRPV1Mgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGRldGVjdGVkLiBSZWJvb3RpbmcgaW4gJSVpIHNlY29uZHMuLi4gUHJlc3MgQ3Ry >> "%PAYLOAD_B64_TEMP%"
echo bCtDIHRvIFJlYm9vdC4NCiAgICBjc2NyaXB0IC8vbm9sb2dvICIlVEVNUCVccy52 >> "%PAYLOAD_B64_TEMP%"
echo YnMiDQopDQoNCmVjaG8uDQplY2hvIFJlYm9vdGluZyBub3cuLi4NCmNhbGwgOkxv >> "%PAYLOAD_B64_TEMP%"
echo ZyAiW0ZBVEFMXSAlKiINCndwZXV0aWwgcmVib290DQpleGl0IC9iIDENCg0KOkVu >> "%PAYLOAD_B64_TEMP%"
echo ZFNjcmlwdA0KY2FsbCA6TG9nICI9PT09PT09PT09PT09PT09PSBXaW5SRSBTY3Jp >> "%PAYLOAD_B64_TEMP%"
echo cHQgU2Vzc2lvbiBFbmRlZCA9PT09PT09PT09PT09PT09PSINCjo6IEZpbmFsIGR1 >> "%PAYLOAD_B64_TEMP%"
echo bXANCmNhbGwgOkR1bXBUZW1wTG9nDQpleGl0IC9iICVlcnJvcmxldmVsJQ== >> "%PAYLOAD_B64_TEMP%"
echo -----END CERTIFICATE----- >> "%PAYLOAD_B64_TEMP%"

if exist "%TEMP%\%PAYLOAD_FILENAME%" (
    echo [INFO] Removing existing payload file... >> "%LOGFILE%"
    del /f "%TEMP%\%PAYLOAD_FILENAME%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Could not remove existing payload file >> "%LOGFILE%"
        del "%PAYLOAD_B64_TEMP%" >nul 2>&1
        exit /b 1
    )
)

echo [INFO] Decoding payload... >> "%LOGFILE%"
certutil -decode "%PAYLOAD_B64_TEMP%" "%TEMP%\%PAYLOAD_FILENAME%" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to decode base64 payload >> "%LOGFILE%"
    del "%PAYLOAD_B64_TEMP%" >nul 2>&1
    exit /b 1
)

del "%PAYLOAD_B64_TEMP%" >nul 2>&1
echo [INFO] Payload extracted successfully >> "%LOGFILE%"
goto :eof

