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
set "REG_HINT=HKLM\SOFTWARE\ESETReset"
set "LOG_PATH=%~dp0ESET_Reset_Tool.log"

:: Fast UAC Check
>nul 2>&1 fsutil dirty query %systemdrive% || (
    echo Requesting administrator privileges...
    powershell -NoProfile -C "$p=@{FilePath='%~f0';Verb='RunAs'};if('%*'){$p['ArgumentList']='%*'};Start-Process @p"
    exit /b
)
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
dism /cleanup-wim >> "%LOGFILE%" 2>&1
mkdir "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
goto :eof

:: =================================================================
:extract_payload
echo [INFO] Creating base64 temp file... >> "%LOGFILE%"

:: BASE64_PAYLOAD_PLACEHOLDER - Build script will replace this line
echo -----BEGIN CERTIFICATE----- > "%PAYLOAD_B64_TEMP%"
echo QGVjaG8gb2ZmDQpzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo IEVTRVQgUmVnaXN0cnkgUmVzZXQgU2NyaXB0IGZvciBXaW5SRQ0KZWNobyA9PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCndwZXV0aWwg >> "%PAYLOAD_B64_TEMP%"
echo Q3JlYXRlQ29uc29sZSA+bnVsIDI+JjENCg0KOjogU2ltcGxlIGxvZ2dpbmcgc2V0 >> "%PAYLOAD_B64_TEMP%"
echo dXAgLSBvbmx5IG5lZWQgdGVtcCBmaWxlDQpzZXQgVEVNUF9MT0dGSUxFPVg6XGVz >> "%PAYLOAD_B64_TEMP%"
echo ZXRfcmVzZXQubG9nDQpzZXQgTUFJTl9MT0dGSUxFPQ0Kc2V0IE5PTklOVEVSQUNU >> "%PAYLOAD_B64_TEMP%"
echo SVZFPTANCnNldCBFWElUQ09ERT0wDQoNCjo6IENhcHR1cmUgV2luUEUgc2hlbGwg >> "%PAYLOAD_B64_TEMP%"
echo bG9nDQppZiBleGlzdCAiWDpcV2luZG93c1xTeXN0ZW0zMlx3aW5wZXNobC5sb2ci >> "%PAYLOAD_B64_TEMP%"
echo ICgNCiAgICBlY2hvIFslZGF0ZSUgJXRpbWUlXSA9PT0gV2luUEUgU2hlbGwgTG9n >> "%PAYLOAD_B64_TEMP%"
echo IENvbnRlbnRzID09PT0+PiIlVEVNUF9MT0dGSUxFJSINCiAgICB0eXBlICJYOlxX >> "%PAYLOAD_B64_TEMP%"
echo aW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmxvZyI+PiIlVEVNUF9MT0dGSUxFJSIg >> "%PAYLOAD_B64_TEMP%"
echo Mj5udWwNCiAgICBlY2hvIFslZGF0ZSUgJXRpbWUlXSA9PT0gRW5kIFdpblBFIFNo >> "%PAYLOAD_B64_TEMP%"
echo ZWxsIExvZyA9PT0+PiIlVEVNUF9MT0dGSUxFJSINCikNCg0KY2FsbCA6TG9nICI9 >> "%PAYLOAD_B64_TEMP%"
echo PT0gV2luUkUgU2NyaXB0IFNlc3Npb24gU3RhcnRlZCA9PT0iDQpjYWxsIDpMb2cg >> "%PAYLOAD_B64_TEMP%"
echo IkVTRVQgUmVnaXN0cnkgUmVzZXQgU2NyaXB0IGZvciBXaW5QRS9XaW5SRSINCg0K >> "%PAYLOAD_B64_TEMP%"
echo OjogSW5pdGlhbGl6ZSB2YXJpYWJsZXMNCnNldCBPRkZMSU5FX1dJTkRSSVZFPQ0K >> "%PAYLOAD_B64_TEMP%"
echo c2V0IE9GRkxJTkVfV0lORElSPQ0KDQo6OiBTY2FuIGZvciBXaW5kb3dzIGluc3Rh >> "%PAYLOAD_B64_TEMP%"
echo bGxhdGlvbg0KY2FsbCA6TG9nICJTY2FubmluZyBmb3IgV2luZG93cyBpbnN0YWxs >> "%PAYLOAD_B64_TEMP%"
echo YXRpb24uLi4iDQoNCmZvciAlJUQgaW4gKEMgRCBFIEYgRyBIIEkgSiBLIEwgTSBO >> "%PAYLOAD_B64_TEMP%"
echo IE8gUCBRIFIgUyBUIFUgViBXIFkgWikgZG8gKA0KICAgIGlmIGV4aXN0ICIlJUQ6 >> "%PAYLOAD_B64_TEMP%"
echo XFdpbmRvd3NcU3lzdGVtMzJcQ29uZmlnXFNPRlRXQVJFIiAoDQogICAgICAgIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCBPRkZMSU5FX1dJTkRSSVZFPSUlRDoNCiAgICAgICAgc2V0IE9GRkxJTkVfV0lO >> "%PAYLOAD_B64_TEMP%"
echo RElSPSUlRDpcV2luZG93cw0KICAgICAgICBjYWxsIDpMb2cgIkZvdW5kIFdpbmRv >> "%PAYLOAD_B64_TEMP%"
echo d3MgaW5zdGFsbGF0aW9uIG9uOiAlJUQ6Ig0KICAgICAgICBnb3RvIDpGb3VuZElu >> "%PAYLOAD_B64_TEMP%"
echo c3RhbGxhdGlvbg0KICAgICkNCikNCg0KY2FsbCA6TG9nICJbRkFUQUxdIE5vIFdp >> "%PAYLOAD_B64_TEMP%"
echo bmRvd3MgaW5zdGFsbGF0aW9uIGZvdW5kIg0KY2FsbCA6Tm9XaW5kb3dzV2Fybmlu >> "%PAYLOAD_B64_TEMP%"
echo ZyAiTm8gV2luZG93cyBpbnN0YWxsYXRpb24gZm91bmQgb24gYW55IGRyaXZlIg0K >> "%PAYLOAD_B64_TEMP%"
echo Z290byA6RW5kU2NyaXB0DQoNCjpGb3VuZEluc3RhbGxhdGlvbg0KY2FsbCA6TG9n >> "%PAYLOAD_B64_TEMP%"
echo ICJTZWxlY3RlZCBXaW5kb3dzIGluc3RhbGxhdGlvbjogJU9GRkxJTkVfV0lORElS >> "%PAYLOAD_B64_TEMP%"
echo JSINCg0KOjogRGVsZXRlIEVTRVQgbGljZW5zZSBmaWxlDQpjYWxsIDpMb2cgIkRl >> "%PAYLOAD_B64_TEMP%"
echo bGV0aW5nIEVTRVQgbGljZW5zZSBmaWxlLi4uIg0Kc2V0IExJQ0VOU0VQQVRIPSVP >> "%PAYLOAD_B64_TEMP%"
echo RkZMSU5FX1dJTkRSSVZFJVxQcm9ncmFtRGF0YVxFU0VUXEVTRVQgU2VjdXJpdHlc >> "%PAYLOAD_B64_TEMP%"
echo TGljZW5zZVxsaWNlbnNlLmxmDQppZiBleGlzdCAiJUxJQ0VOU0VQQVRIJSIgKA0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgIGF0dHJpYiAtciAtaCAtcyAiJUxJQ0VOU0VQQVRIJSIgPm51bCAyPiYxDQog >> "%PAYLOAD_B64_TEMP%"
echo ICAgZGVsIC9mICIlTElDRU5TRVBBVEglIiA+bnVsIDI+JjENCiAgICBpZiBleGlz >> "%PAYLOAD_B64_TEMP%"
echo dCAiJUxJQ0VOU0VQQVRIJSIgKA0KICAgICAgICBjYWxsIDpMb2cgIltXQVJOXSBG >> "%PAYLOAD_B64_TEMP%"
echo YWlsZWQgdG8gZGVsZXRlIGxpY2Vuc2UgZmlsZSINCiAgICApIGVsc2UgKA0KICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICBjYWxsIDpMb2cgIkxpY2Vuc2UgZmlsZSBkZWxldGVkIHN1Y2Nlc3NmdWxs >> "%PAYLOAD_B64_TEMP%"
echo eSINCiAgICApDQopIGVsc2UgKA0KICAgIGNhbGwgOkxvZyAiTGljZW5zZSBmaWxl >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBmb3VuZCINCikNCg0KOjogTG9hZCB0aGUgU09GVFdBUkUgaGl2ZQ0KY2Fs >> "%PAYLOAD_B64_TEMP%"
echo bCA6TG9nICJMb2FkaW5nIG9mZmxpbmUgU09GVFdBUkUgaGl2ZS4uLiINCnJlZyBs >> "%PAYLOAD_B64_TEMP%"
echo b2FkIEhLTE1cT0ZGTElORV9TT0ZUV0FSRSAiJU9GRkxJTkVfV0lORElSJVxTeXN0 >> "%PAYLOAD_B64_TEMP%"
echo ZW0zMlxDb25maWdcU09GVFdBUkUiID5udWwgMj4mMQ0KaWYgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo ICgNCiAgICBjYWxsIDpGYXRhbEVycm9yICJGYWlsZWQgdG8gbG9hZCBTT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RSBoaXZlIg0KKQ0KY2FsbCA6TG9nICJTT0ZUV0FSRSBoaXZlIGxvYWRlZCBzdWNj >> "%PAYLOAD_B64_TEMP%"
echo ZXNzZnVsbHkiDQoNCjo6IFNJTVBMSUZJRUQ6IEdldCBtYWluIGxvZyBwYXRoIGFu >> "%PAYLOAD_B64_TEMP%"
echo ZCBkbyBpbml0aWFsIGR1bXANCmNhbGwgOkxvZyAiUmV0cmlldmluZyBsb2cgcGF0 >> "%PAYLOAD_B64_TEMP%"
echo aCBmcm9tIHJlZ2lzdHJ5Li4uIg0KY2FsbCA6U2V0dXBNYWluTG9nZ2luZw0KDQo6 >> "%PAYLOAD_B64_TEMP%"
echo OiBQZXJmb3JtIGFsbCByZWdpc3RyeSBvcGVyYXRpb25zDQpjYWxsIDpMb2cgIlN0 >> "%PAYLOAD_B64_TEMP%"
echo YXJ0aW5nIEVTRVQgcmVnaXN0cnkgbW9kaWZpY2F0aW9ucy4uLiINCg0KOjogQ291 >> "%PAYLOAD_B64_TEMP%"
echo bnRlciBmb3Igb3BlcmF0aW9ucw0Kc2V0IE9QUz0wDQoNClJlZy5leGUgZGVsZXRl >> "%PAYLOAD_B64_TEMP%"
echo ICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJl >> "%PAYLOAD_B64_TEMP%"
echo bnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5c >> "%PAYLOAD_B64_TEMP%"
echo Q2hlY2siIC92ICJDZmdTZXFOdW1iZXJFc2V0QWNjR2xvYmFsIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0 >> "%PAYLOAD_B64_TEMP%"
echo eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5n >> "%PAYLOAD_B64_TEMP%"
echo c1xFa3JuXENoZWNrIiAvdiAiRE5TVGltZXJTZWMiIC9mID5udWwgMj4mMQ0KaWYg >> "%PAYLOAD_B64_TEMP%"
echo bm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cQ2hl >> "%PAYLOAD_B64_TEMP%"
echo Y2siIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5F >> "%PAYLOAD_B64_TEMP%"
echo X1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25m >> "%PAYLOAD_B64_TEMP%"
echo aWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEVjcCIgL3YgIlNlYXRJ >> "%PAYLOAD_B64_TEMP%"
echo RCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMr >> "%PAYLOAD_B64_TEMP%"
echo PTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEw >> "%PAYLOAD_B64_TEMP%"
echo MDAwMDZcc2V0dGluZ3NcRWtyblxFY3AiIC92ICJDb21wdXRlck5hbWUiIC9mID5u >> "%PAYLOAD_B64_TEMP%"
echo dWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJl >> "%PAYLOAD_B64_TEMP%"
echo Zy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNl >> "%PAYLOAD_B64_TEMP%"
echo Y3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNl >> "%PAYLOAD_B64_TEMP%"
echo dHRpbmdzXEVrcm5cRWNwIiAvdiAiVG9rZW4iIC9mID5udWwgMj4mMQ0KaWYgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xN >> "%PAYLOAD_B64_TEMP%"
echo XE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJz >> "%PAYLOAD_B64_TEMP%"
echo aW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cRWNwIiAv >> "%PAYLOAD_B64_TEMP%"
echo ZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBs >> "%PAYLOAD_B64_TEMP%"
echo dWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvIiAvdiAiTGFzdEh3ZiIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAw >> "%PAYLOAD_B64_TEMP%"
echo MDZcc2V0dGluZ3NcRWtyblxJbmZvIiAvdiAiQWN0aXZhdGlvblN0YXRlIiAvZiA+ >> "%PAYLOAD_B64_TEMP%"
echo bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpS >> "%PAYLOAD_B64_TEMP%"
echo ZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBT >> "%PAYLOAD_B64_TEMP%"
echo ZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxz >> "%PAYLOAD_B64_TEMP%"
echo ZXR0aW5nc1xFa3JuXEluZm8iIC92ICJBY3RpdmF0aW9uVHlwZSIgL2YgPm51bCAy >> "%PAYLOAD_B64_TEMP%"
echo PiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4 >> "%PAYLOAD_B64_TEMP%"
echo ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJp >> "%PAYLOAD_B64_TEMP%"
echo dHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGlu >> "%PAYLOAD_B64_TEMP%"
echo Z3NcRWtyblxJbmZvIiAvdiAiTGFzdEFjdGl2YXRpb25EYXRlIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxD >> "%PAYLOAD_B64_TEMP%"
echo dXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xF >> "%PAYLOAD_B64_TEMP%"
echo a3JuXEluZm8iIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxP >> "%PAYLOAD_B64_TEMP%"
echo RkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lv >> "%PAYLOAD_B64_TEMP%"
echo blxDb25maWdccGx1Z2luc1wwMTAwMDIwMFxzZXR0aW5nc1xzdFByb3RvY29sRmls >> "%PAYLOAD_B64_TEMP%"
echo dGVyaW5nXHN0QXBwU3NsIiAvdiAidVJvb3RDcmVhdGVUaW1lIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxD >> "%PAYLOAD_B64_TEMP%"
echo dXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDIwMFxzZXR0aW5nc1xz >> "%PAYLOAD_B64_TEMP%"
echo dFByb3RvY29sRmlsdGVyaW5nXHN0QXBwU3NsIiAvZiA+bnVsIDI+JjENCg0KUmVn >> "%PAYLOAD_B64_TEMP%"
echo LmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2Vj >> "%PAYLOAD_B64_TEMP%"
echo dXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdCYWNr >> "%PAYLOAD_B64_TEMP%"
echo dXAiIC92ICJVc2VybmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl >> "%PAYLOAD_B64_TEMP%"
echo bCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElO >> "%PAYLOAD_B64_TEMP%"
echo RV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cUGx1 >> "%PAYLOAD_B64_TEMP%"
echo Z2luc1wwMTAwMDQwMFxDb25maWdCYWNrdXAiIC92ICJQYXNzd29yZCIgL2YgPm51 >> "%PAYLOAD_B64_TEMP%"
echo bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVn >> "%PAYLOAD_B64_TEMP%"
echo LmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2Vj >> "%PAYLOAD_B64_TEMP%"
echo dXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdCYWNr >> "%PAYLOAD_B64_TEMP%"
echo dXAiIC92ICJMZWdhY3lVc2VybmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJy >> "%PAYLOAD_B64_TEMP%"
echo b3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1c >> "%PAYLOAD_B64_TEMP%"
echo T0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNp >> "%PAYLOAD_B64_TEMP%"
echo b25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdCYWNrdXAiIC92ICJMZWdhY3lQYXNz >> "%PAYLOAD_B64_TEMP%"
echo d29yZCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBP >> "%PAYLOAD_B64_TEMP%"
echo UFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQwMFxD >> "%PAYLOAD_B64_TEMP%"
echo b25maWdCYWNrdXAiIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtM >> "%PAYLOAD_B64_TEMP%"
echo TVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVy >> "%PAYLOAD_B64_TEMP%"
echo c2lvblxDb25maWdccGx1Z2luc1wwMTAwMDQwMFxzZXR0aW5ncyIgL3YgIlBhc3N3 >> "%PAYLOAD_B64_TEMP%"
echo b3JkIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9Q >> "%PAYLOAD_B64_TEMP%"
echo Uys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1ww >> "%PAYLOAD_B64_TEMP%"
echo MTAwMDQwMFxzZXR0aW5ncyIgL3YgIlVzZXJuYW1lIiAvZiA+bnVsIDI+JjENCmlm >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFkZCAi >> "%PAYLOAD_B64_TEMP%"
echo SEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50 >> "%PAYLOAD_B64_TEMP%"
echo VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDQwMFxzZXR0aW5ncyIgL2YgPm51 >> "%PAYLOAD_B64_TEMP%"
echo bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5z >> "%PAYLOAD_B64_TEMP%"
echo XDAxMDAwNjAwXHNldHRpbmdzXERpc3RQYWNrYWdlXEFwcFNldHRpbmdzIiAvdiAi >> "%PAYLOAD_B64_TEMP%"
echo QWN0T3B0aW9ucyIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdp >> "%PAYLOAD_B64_TEMP%"
echo bnNcMDEwMDA2MDBcc2V0dGluZ3NcRGlzdFBhY2thZ2VcQXBwU2V0dGluZ3MiIC9m >> "%PAYLOAD_B64_TEMP%"
echo ID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRX >> "%PAYLOAD_B64_TEMP%"
echo QVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1 >> "%PAYLOAD_B64_TEMP%"
echo Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEluZm9cTGFzdEh3SW5mbyIgL3Yg >> "%PAYLOAD_B64_TEMP%"
echo IkNvbXB1dGVyTmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo IHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9T >> "%PAYLOAD_B64_TEMP%"
echo T0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmln >> "%PAYLOAD_B64_TEMP%"
echo XHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvXExhc3RId0luZm8i >> "%PAYLOAD_B64_TEMP%"
echo IC92ICJWZXJzaW9uIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEg >> "%PAYLOAD_B64_TEMP%"
echo c2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRX >> "%PAYLOAD_B64_TEMP%"
echo QVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1 >> "%PAYLOAD_B64_TEMP%"
echo Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEluZm9cTGFzdEh3SW5mbyIgL2Yg >> "%PAYLOAD_B64_TEMP%"
echo Pm51bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJF >> "%PAYLOAD_B64_TEMP%"
echo ZGl0aW9uTmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3Yg >> "%PAYLOAD_B64_TEMP%"
echo IkZ1bGxQcm9kdWN0TmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl >> "%PAYLOAD_B64_TEMP%"
echo bCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElO >> "%PAYLOAD_B64_TEMP%"
echo RV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5m >> "%PAYLOAD_B64_TEMP%"
echo byIgL3YgIkluc3RhbGxlZEJ5RVJBIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv >> "%PAYLOAD_B64_TEMP%"
echo cmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxP >> "%PAYLOAD_B64_TEMP%"
echo RkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lv >> "%PAYLOAD_B64_TEMP%"
echo blxJbmZvIiAvdiAiQWN0aXZlRmVhdHVyZXMiIC9mID5udWwgMj4mMQ0KaWYgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXEluZm8iIC92ICJVbmlxdWVJZCIgL2YgPm51bCAyPiYxDQppZiBub3Qg >> "%PAYLOAD_B64_TEMP%"
echo ZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhL >> "%PAYLOAD_B64_TEMP%"
echo TE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZl >> "%PAYLOAD_B64_TEMP%"
echo cnNpb25cSW5mbyIgL3YgIldlYkFjdGl2YXRpb25TdGF0ZSIgL2YgPm51bCAyPiYx >> "%PAYLOAD_B64_TEMP%"
echo DQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBk >> "%PAYLOAD_B64_TEMP%"
echo ZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlc >> "%PAYLOAD_B64_TEMP%"
echo Q3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYlNlYXRJZCIgL2YgPm51bCAyPiYx >> "%PAYLOAD_B64_TEMP%"
echo DQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBk >> "%PAYLOAD_B64_TEMP%"
echo ZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlc >> "%PAYLOAD_B64_TEMP%"
echo Q3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYkNsaWVudENvbXB1dGVyTmFtZSIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYkxpY2Vuc2VQ >> "%PAYLOAD_B64_TEMP%"
echo dWJsaWNJZCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAv >> "%PAYLOAD_B64_TEMP%"
echo YSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIkxh >> "%PAYLOAD_B64_TEMP%"
echo c3RBY3RpdmF0aW9uUmVzdWx0IiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxl >> "%PAYLOAD_B64_TEMP%"
echo dmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFkZCAiSEtMTVxPRkZMSU5F >> "%PAYLOAD_B64_TEMP%"
echo X1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJbmZv >> "%PAYLOAD_B64_TEMP%"
echo IiAvZiA+bnVsIDI+JjENCg0KY2FsbCA6TG9nICJSZWdpc3RyeSBtb2RpZmljYXRp >> "%PAYLOAD_B64_TEMP%"
echo b25zIGNvbXBsZXRlIC0gU3VjY2Vzc2Z1bGx5IGRlbGV0ZWQgJU9QUyUgdmFsdWVz >> "%PAYLOAD_B64_TEMP%"
echo Ig0KDQo6OiBVbmxvYWQgdGhlIGhpdmUNCmNhbGwgOkxvZyAiVW5sb2FkaW5nIFNP >> "%PAYLOAD_B64_TEMP%"
echo RlRXQVJFIGhpdmUuLi4iDQpyZWcgdW5sb2FkIEhLTE1cT0ZGTElORV9TT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RSA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogICAgY2FsbCA6TG9nICJb >> "%PAYLOAD_B64_TEMP%"
echo V0FSTl0gRmFpbGVkIHRvIHVubG9hZCBoaXZlIG9uIGZpcnN0IGF0dGVtcHQsIHJl >> "%PAYLOAD_B64_TEMP%"
echo dHJ5aW5nLi4uIg0KICAgIGVjaG8gV1NjcmlwdC5TbGVlcCAzMDAwID4iJVRFTVAl >> "%PAYLOAD_B64_TEMP%"
echo XHMzLnZicyINCiAgICBjc2NyaXB0IC8vbm9sb2dvICIlVEVNUCVcczMudmJzIg0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgIHJlZyB1bmxvYWQgSEtMTVxPRkZMSU5FX1NPRlRXQVJFID5udWwgMj4mMQ0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgICAgIGNhbGwgOkxvZyAiW0VSUk9S >> "%PAYLOAD_B64_TEMP%"
echo XSBGYWlsZWQgdG8gdW5sb2FkIGhpdmUgYWZ0ZXIgcmV0cnkgLSB3aWxsIHJlbWFp >> "%PAYLOAD_B64_TEMP%"
echo biBsb2FkZWQgdW50aWwgcmVzdGFydCINCiAgICApIGVsc2UgKA0KICAgICAgICBj >> "%PAYLOAD_B64_TEMP%"
echo YWxsIDpMb2cgIkhpdmUgdW5sb2FkZWQgc3VjY2Vzc2Z1bGx5IG9uIHJldHJ5Ig0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgICkNCikgZWxzZSAoDQogICAgY2FsbCA6TG9nICJIaXZlIHVubG9hZGVkIHN1 >> "%PAYLOAD_B64_TEMP%"
echo Y2Nlc3NmdWxseSINCikNCg0KY2FsbCA6TG9nICJTVUNDRVNTOiBFU0VULVJlc2V0 >> "%PAYLOAD_B64_TEMP%"
echo IGNvbXBsZXRlIg0KY2FsbCA6TG9nICJUYXJnZXQgc3lzdGVtOiAlT0ZGTElORV9X >> "%PAYLOAD_B64_TEMP%"
echo SU5ESVIlIg0KY2FsbCA6TG9nICJSZWdpc3RyeSB2YWx1ZXMgZGVsZXRlZDogJU9Q >> "%PAYLOAD_B64_TEMP%"
echo UyUiDQpjYWxsIDpMb2cgIk5PVEU6IEVTRVQgd2lsbCBuZWVkIHRvIGJlIHJlYWN0 >> "%PAYLOAD_B64_TEMP%"
echo aXZhdGVkIHdoZW4gV2luZG93cyBib290cyINCg0KZWNoby4NCmVjaG8gPT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCmVjaG8gICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICAgRVNFVCBSRVNFVCBDT01QTEVURUQNCmVjaG8gPT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCmVjaG8uDQplY2hvIFRhcmdl >> "%PAYLOAD_B64_TEMP%"
echo dCBTeXN0ZW06ICVPRkZMSU5FX1dJTkRJUiUNCmVjaG8gUmVnaXN0cnkgVmFsdWVz >> "%PAYLOAD_B64_TEMP%"
echo IERlbGV0ZWQ6ICVPUFMlDQplY2hvLg0KZWNobyBFU0VUIHdpbGwgbmVlZCB0byBi >> "%PAYLOAD_B64_TEMP%"
echo ZSByZWFjdGl2YXRlZCB3aGVuIFdpbmRvd3MgYm9vdHMuDQplY2hvLg0KZWNobyBS >> "%PAYLOAD_B64_TEMP%"
echo ZWJvb3RpbmcgaW4gNyBzZWNvbmRzLi4uDQoNCjo6IDctc2Vjb25kIGRlbGF5DQpl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIFdTY3JpcHQuU2xlZXAgNzAwMCA+IiVURU1QJVxzNy52YnMiDQpjc2NyaXB0 >> "%PAYLOAD_B64_TEMP%"
echo IC8vbm9sb2dvICIlVEVNUCVcczcudmJzIg0KDQplY2hvLg0KZWNobyBSZWJvb3Rp >> "%PAYLOAD_B64_TEMP%"
echo bmcgbm93Li4uDQpjYWxsIDpMb2cgIkluaXRpYXRpbmcgc3lzdGVtIHJlYm9vdC4u >> "%PAYLOAD_B64_TEMP%"
echo LiINCg0Kd3BldXRpbCByZWJvb3QNCmdvdG8gOkVuZFNjcmlwdA0KDQo6OiBTSU1Q >> "%PAYLOAD_B64_TEMP%"
echo TElGSUVEIEZVTkNUSU9OUw0KDQo6TG9nDQpzZXQgImxvZ3RleHQ9JSoiDQpzZXQg >> "%PAYLOAD_B64_TEMP%"
echo ImxvZ3RleHQ9IWxvZ3RleHQ6Ij0hIg0KZWNobyAhbG9ndGV4dCENCmlmIGRlZmlu >> "%PAYLOAD_B64_TEMP%"
echo ZWQgTUFJTl9MT0dGSUxFICgNCiAgICBlY2hvIFslZGF0ZSUgJXRpbWUlXSAhbG9n >> "%PAYLOAD_B64_TEMP%"
echo dGV4dCE+PiIlTUFJTl9MT0dGSUxFJSIgMj5udWwNCikgZWxzZSAoDQogICAgZWNo >> "%PAYLOAD_B64_TEMP%"
echo byBbJWRhdGUlICV0aW1lJV0gIWxvZ3RleHQhPj4iJVRFTVBfTE9HRklMRSUiDQop >> "%PAYLOAD_B64_TEMP%"
echo DQpnb3RvIDplb2YNCg0KOlNldHVwTWFpbkxvZ2dpbmcgDQo6OiBHZXQgbG9nIHBh >> "%PAYLOAD_B64_TEMP%"
echo dGggZnJvbSByZWdpc3RyeSBhbmQgc2V0IHVwIG1haW4gbG9nIGZpbGUNCnNldCAi >> "%PAYLOAD_B64_TEMP%"
echo TE9HX1BBVEg9Ig0KZm9yIC9mICJ0b2tlbnM9MiwqIiAlJUEgaW4gKCdyZWcgcXVl >> "%PAYLOAD_B64_TEMP%"
echo cnkgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUUmVzZXQiIC92IExvZ1BhdGgg >> "%PAYLOAD_B64_TEMP%"
echo Ml4+bnVsIF58IGZpbmQgIlJFR19TWiInKSBkbyBzZXQgIkxPR19QQVRIPSUlQiIN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KaWYgZGVmaW5lZCBMT0dfUEFUSCAoDQogICAgY2FsbCA6TG9nICJMb2cgcGF0 >> "%PAYLOAD_B64_TEMP%"
echo aCBmb3VuZDogJUxPR19QQVRIJSINCiAgICANCiAgICA6OiBQYXRoIG1hcHBpbmcg >> "%PAYLOAD_B64_TEMP%"
echo LSByZXBsYWNlIEM6IHdpdGggZGV0ZWN0ZWQgZHJpdmUNCiAgICBzZXQgIk1BSU5f >> "%PAYLOAD_B64_TEMP%"
echo TE9HRklMRT0lT0ZGTElORV9XSU5EUklWRSUlTE9HX1BBVEg6fjIlIg0KICAgIA0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgIGNhbGwgOkxvZyAiTG9nIE1hcHBlZCB0byBXaW5SRSBwYXRoOiAhTUFJTl9M >> "%PAYLOAD_B64_TEMP%"
echo T0dGSUxFISINCiAgICANCiAgICA6OiBEbyBpbml0aWFsIGR1bXANCiAgICBjYWxs >> "%PAYLOAD_B64_TEMP%"
echo IDpEdW1wVGVtcExvZw0KICAgIGNhbGwgOkxvZyAiQ29udGludWVkIGZyb20gdGVt >> "%PAYLOAD_B64_TEMP%"
echo cCBsb2ciDQopIGVsc2UgKA0KICAgIGNhbGwgOkxvZyAiW1dBUk5dIExvZyBwYXRo >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBmb3VuZCBpbiByZWdpc3RyeSwgY29udGludWluZyB3aXRoIHRlbXAgbG9n >> "%PAYLOAD_B64_TEMP%"
echo IG9ubHkiDQopDQpnb3RvIDplb2YNCg0KOkR1bXBUZW1wTG9nDQo6OiBEdW1wIHRl >> "%PAYLOAD_B64_TEMP%"
echo bXAgbG9nIHRvIG1haW4gbG9nIGlmIHdlIGhhdmUgb25lDQppZiBkZWZpbmVkIE1B >> "%PAYLOAD_B64_TEMP%"
echo SU5fTE9HRklMRSAoDQogICAgaWYgZXhpc3QgIiVURU1QX0xPR0ZJTEUlIiAoDQog >> "%PAYLOAD_B64_TEMP%"
echo ICAgICAgIGVjaG8gWyVkYXRlJSAldGltZSVdID09PSBEdW1waW5nIHRlbXAgbG9n >> "%PAYLOAD_B64_TEMP%"
echo IGNvbnRlbnRzID09PT4+IiVNQUlOX0xPR0ZJTEUlIiAyPm51bA0KICAgICAgICB0 >> "%PAYLOAD_B64_TEMP%"
echo eXBlICIlVEVNUF9MT0dGSUxFJSI+PiIlTUFJTl9MT0dGSUxFJSIgMj5udWwNCiAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICAgZWNobyBbJWRhdGUlICV0aW1lJV0gPT09IEVuZCB0ZW1wIGxvZyBkdW1w >> "%PAYLOAD_B64_TEMP%"
echo ID09PT4+IiVNQUlOX0xPR0ZJTEUlIiAyPm51bA0KICAgICkNCikNCmdvdG8gOmVv >> "%PAYLOAD_B64_TEMP%"
echo Zg0KDQo6RmF0YWxFcnJvcg0Kc2V0ICJFWElUQ09ERT0xIg0KZWNoby4NCmNhbGwg >> "%PAYLOAD_B64_TEMP%"
echo OkxvZyAiW0ZBVEFMXSAlKiINCmVjaG8uDQppZiAiJU5PTklOVEVSQUNUSVZFJSI9 >> "%PAYLOAD_B64_TEMP%"
echo PSIwIiAoDQogICAgZWNobyBBbiB1bnJlY292ZXJhYmxlIGVycm9yIG9jY3VycmVk >> "%PAYLOAD_B64_TEMP%"
echo LiBQbGVhc2UgY2hlY2sgdGhlIGxvZyBmaWxlIGZvciBkZXRhaWxzLg0KICAgIHBh >> "%PAYLOAD_B64_TEMP%"
echo dXNlDQopDQpnb3RvIDpFbmRTY3JpcHQNCg0KOk5vV2luZG93c1dhcm5pbmcNCkBl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIG9mZg0Kc2V0bG9jYWwgRW5hYmxlRXh0ZW5zaW9ucw0KDQo6OiBDcmVhdGUg >> "%PAYLOAD_B64_TEMP%"
echo dGhlIDEtc2Vjb25kIHNsZWVwIHV0aWxpdHkNCmVjaG8gV1NjcmlwdC5TbGVlcCAx >> "%PAYLOAD_B64_TEMP%"
echo MDAwID4iJVRFTVAlXHMudmJzIg0KDQpjbHMNCmNvbG9yIDRGDQplY2hvLg0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo byA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQ0K >> "%PAYLOAD_B64_TEMP%"
echo ZWNobyBXQVJOSU5HOiBXSU5ET1dTIElOU1RBTExBVElPTiBOT1QgREVURUNURUQN >> "%PAYLOAD_B64_TEMP%"
echo CmVjaG8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT0NCmVjaG8uDQplY2hvICUqDQplY2hvLg0KZWNobyBIZXkgbWFuLiBIb3cgZGlk >> "%PAYLOAD_B64_TEMP%"
echo IHlvdSBwdWxsIHRoaXMgb2ZmPyBUaGlzIHNjcmlwdCByZXF1aXJlcyBXSU5ET1dT >> "%PAYLOAD_B64_TEMP%"
echo IHRvIGJlIGluc3RhbGxlZC4NCmVjaG8uDQoNCjo6IENvdW50ZG93biBieSBwcmlu >> "%PAYLOAD_B64_TEMP%"
echo dGluZyBhIG5ldyBsaW5lIGVhY2ggc2Vjb25kDQpmb3IgL0wgJSVpIGluICgxNSwt >> "%PAYLOAD_B64_TEMP%"
echo MSwxKSBkbyAoDQogICAgZWNobyBXSU5ET1dTIG5vdCBkZXRlY3RlZC4gUmVib290 >> "%PAYLOAD_B64_TEMP%"
echo aW5nIGluICUlaSBzZWNvbmRzLi4uIFByZXNzIEN0cmwrQyB0byBSZWJvb3QgTm93 >> "%PAYLOAD_B64_TEMP%"
echo Lg0KICAgIGNzY3JpcHQgLy9ub2xvZ28gIiVURU1QJVxzLnZicyINCikNCg0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo by4NCmVjaG8gUmVib290aW5nIG5vdy4uLg0KY2FsbCA6TG9nICJbRkFUQUxdICUq >> "%PAYLOAD_B64_TEMP%"
echo IiAgDQp3cGV1dGlsIHJlYm9vdA0KZW5kbG9jYWwgJiBzZXQgIkVYSVRDT0RFPTEi >> "%PAYLOAD_B64_TEMP%"
echo ICYgZXhpdCAvYiAxDQoNCjpFbmRTY3JpcHQNCmNhbGwgOkxvZyAiPT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT0gV2luUkUgU2NyaXB0IFNlc3Npb24gRW5kZWQgPT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT0iDQo6OiBGaW5hbCBkdW1wDQpjYWxsIDpEdW1wVGVtcExvZw0KZXhpdCAv >> "%PAYLOAD_B64_TEMP%"
echo YiAlRVhJVENPREUl >> "%PAYLOAD_B64_TEMP%"
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

