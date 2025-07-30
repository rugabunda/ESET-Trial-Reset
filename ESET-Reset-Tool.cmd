@echo off
setlocal enabledelayedexpansion
title ESET Offline Reset Tool v5.0

:: =================================================================
:: ESET Offline Reset Management Tool - v5.0 (Base64 Method)
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
echo                         Version 5.0
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

echo.
echo  IMPORTANT: Close any file explorers and command prompts using %MOUNT_DIR% before continuing.
echo.
pause
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
echo PT4+IiVURU1QX0xPR0ZJTEUlIg0KICAgIGVjaG8uPj4iJVRFTVBfTE9HRklMRSUi >> "%PAYLOAD_B64_TEMP%"
echo DQopDQoNCmNhbGwgOkxvZyAiPT09IFdpblJFIFNjcmlwdCBTZXNzaW9uIFN0YXJ0 >> "%PAYLOAD_B64_TEMP%"
echo ZWQgPT09Ig0KY2FsbCA6TG9nICJFU0VUIFJlZ2lzdHJ5IFJlc2V0IFNjcmlwdCBm >> "%PAYLOAD_B64_TEMP%"
echo b3IgV2luUEUvV2luUkUiDQoNCjo6IEluaXRpYWxpemUgdmFyaWFibGVzDQpzZXQg >> "%PAYLOAD_B64_TEMP%"
echo V0lORFJJVkU9DQpzZXQgV0lORElSPQ0KDQo6OiBTY2FuIGZvciBXaW5kb3dzIGlu >> "%PAYLOAD_B64_TEMP%"
echo c3RhbGxhdGlvbg0KY2FsbCA6TG9nICJTY2FubmluZyBmb3IgV2luZG93cyBpbnN0 >> "%PAYLOAD_B64_TEMP%"
echo YWxsYXRpb24uLi4iDQoNCmZvciAlJUQgaW4gKEMgRCBFIEYgRyBIIEkgSiBLIEwg >> "%PAYLOAD_B64_TEMP%"
echo TSBOIE8gUCBRIFIgUyBUIFUgViBXIFggWSBaKSBkbyAoDQogICAgaWYgZXhpc3Qg >> "%PAYLOAD_B64_TEMP%"
echo IiUlRDpcV2luZG93c1xTeXN0ZW0zMlxDb25maWdcU09GVFdBUkUiICgNCiAgICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgc2V0IFdJTkRSSVZFPSUlRDoNCiAgICAgICAgc2V0IFdJTkRJUj0lJUQ6XFdp >> "%PAYLOAD_B64_TEMP%"
echo bmRvd3MNCiAgICAgICAgZ290byA6Rm91bmRJbnN0YWxsYXRpb24NCiAgICApDQop >> "%PAYLOAD_B64_TEMP%"
echo DQoNCmNhbGwgOkxvZyAiW0ZBVEFMXSBObyBXaW5kb3dzIGluc3RhbGxhdGlvbiBm >> "%PAYLOAD_B64_TEMP%"
echo b3VuZCINCmNhbGwgOk5vV2luZG93c1dhcm5pbmcgIk5vIFdpbmRvd3MgaW5zdGFs >> "%PAYLOAD_B64_TEMP%"
echo bGF0aW9uIGZvdW5kIG9uIGFueSBkcml2ZSINCmdvdG8gOkVuZFNjcmlwdA0KDQo6 >> "%PAYLOAD_B64_TEMP%"
echo Rm91bmRJbnN0YWxsYXRpb24NCmNhbGwgOkxvZyAiRm91bmQgV2luZG93cyBpbnN0 >> "%PAYLOAD_B64_TEMP%"
echo YWxsYXRpb24gb246ICUlRDoiDQoNCikNCmNhbGwgOkxvZyAiU2VsZWN0ZWQgV2lu >> "%PAYLOAD_B64_TEMP%"
echo ZG93cyBpbnN0YWxsYXRpb246ICVXSU5ESVIlIg0KDQo6OiBEZWxldGUgRVNFVCBs >> "%PAYLOAD_B64_TEMP%"
echo aWNlbnNlIGZpbGUNCmNhbGwgOkxvZyAiRGVsZXRpbmcgRVNFVCBsaWNlbnNlIGZp >> "%PAYLOAD_B64_TEMP%"
echo bGUuLi4iDQpzZXQgTElDRU5TRVBBVEg9JVdJTkRSSVZFJVxQcm9ncmFtRGF0YVxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUXEVTRVQgU2VjdXJpdHlcTGljZW5zZVxsaWNlbnNlLmxmDQppZiBleGlzdCAi >> "%PAYLOAD_B64_TEMP%"
echo JUxJQ0VOU0VQQVRIJSIgKA0KICAgIGF0dHJpYiAtciAtaCAtcyAiJUxJQ0VOU0VQ >> "%PAYLOAD_B64_TEMP%"
echo QVRIJSIgPm51bCAyPiYxDQogICAgZGVsIC9mICIlTElDRU5TRVBBVEglIiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCiAgICBpZiBleGlzdCAiJUxJQ0VOU0VQQVRIJSIgKA0KICAgICAgICBj >> "%PAYLOAD_B64_TEMP%"
echo YWxsIDpMb2cgIltXQVJOXSBGYWlsZWQgdG8gZGVsZXRlIGxpY2Vuc2UgZmlsZSIN >> "%PAYLOAD_B64_TEMP%"
echo CiAgICApIGVsc2UgKA0KICAgICAgICBjYWxsIDpMb2cgIkxpY2Vuc2UgZmlsZSBk >> "%PAYLOAD_B64_TEMP%"
echo ZWxldGVkIHN1Y2Nlc3NmdWxseSINCiAgICApDQopIGVsc2UgKA0KICAgIGNhbGwg >> "%PAYLOAD_B64_TEMP%"
echo OkxvZyAiTGljZW5zZSBmaWxlIG5vdCBmb3VuZCINCikNCg0KOjogTG9hZCB0aGUg >> "%PAYLOAD_B64_TEMP%"
echo U09GVFdBUkUgaGl2ZQ0KY2FsbCA6TG9nICJMb2FkaW5nIG9mZmxpbmUgU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkUgaGl2ZS4uLiINCnJlZyBsb2FkIEhLTE1cT0ZGTElORV9TT0ZUV0FSRSAiJVdJ >> "%PAYLOAD_B64_TEMP%"
echo TkRJUiVcU3lzdGVtMzJcQ29uZmlnXFNPRlRXQVJFIiA+bnVsIDI+JjENCmlmIGVy >> "%PAYLOAD_B64_TEMP%"
echo cm9ybGV2ZWwgMSAoDQogICAgY2FsbCA6RmF0YWxFcnJvciAiRmFpbGVkIHRvIGxv >> "%PAYLOAD_B64_TEMP%"
echo YWQgU09GVFdBUkUgaGl2ZSINCikNCmNhbGwgOkxvZyAiU09GVFdBUkUgaGl2ZSBs >> "%PAYLOAD_B64_TEMP%"
echo b2FkZWQgc3VjY2Vzc2Z1bGx5Ig0KDQo6OiBTSU1QTElGSUVEOiBHZXQgbWFpbiBs >> "%PAYLOAD_B64_TEMP%"
echo b2cgcGF0aCBhbmQgZG8gaW5pdGlhbCBkdW1wDQpjYWxsIDpMb2cgIlJldHJpZXZp >> "%PAYLOAD_B64_TEMP%"
echo bmcgbG9nIHBhdGggZnJvbSByZWdpc3RyeS4uLiINCmNhbGwgOlNldHVwTWFpbkxv >> "%PAYLOAD_B64_TEMP%"
echo Z2dpbmcNCg0KOjogUGVyZm9ybSBhbGwgcmVnaXN0cnkgb3BlcmF0aW9ucw0KY2Fs >> "%PAYLOAD_B64_TEMP%"
echo bCA6TG9nICJTdGFydGluZyBFU0VUIHJlZ2lzdHJ5IG1vZGlmaWNhdGlvbnMuLi4i >> "%PAYLOAD_B64_TEMP%"
echo DQoNCjo6IENvdW50ZXIgZm9yIG9wZXJhdGlvbnMNCnNldCBPUFM9MA0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1 >> "%PAYLOAD_B64_TEMP%"
echo cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0 >> "%PAYLOAD_B64_TEMP%"
echo aW5nc1xFa3JuXENoZWNrIiAvdiAiQ2ZnU2VxTnVtYmVyRXNldEFjY0dsb2JhbCIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAw >> "%PAYLOAD_B64_TEMP%"
echo MDZcc2V0dGluZ3NcRWtyblxDaGVjayIgL3YgIkROU1RpbWVyU2VjIiAvZiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0 >> "%PAYLOAD_B64_TEMP%"
echo eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5n >> "%PAYLOAD_B64_TEMP%"
echo c1xFa3JuXENoZWNrIiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBkZWxldGUgIkhL >> "%PAYLOAD_B64_TEMP%"
echo TE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZl >> "%PAYLOAD_B64_TEMP%"
echo cnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxFY3Ai >> "%PAYLOAD_B64_TEMP%"
echo IC92ICJTZWF0SUQiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBz >> "%PAYLOAD_B64_TEMP%"
echo ZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09G >> "%PAYLOAD_B64_TEMP%"
echo VFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xw >> "%PAYLOAD_B64_TEMP%"
echo bHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cRWNwIiAvdiAiQ29tcHV0ZXJO >> "%PAYLOAD_B64_TEMP%"
echo YW1lIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9Q >> "%PAYLOAD_B64_TEMP%"
echo Uys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1ww >> "%PAYLOAD_B64_TEMP%"
echo MTAwMDAwNlxzZXR0aW5nc1xFa3JuXEVjcCIgL3YgIlRva2VuIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxD >> "%PAYLOAD_B64_TEMP%"
echo dXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xF >> "%PAYLOAD_B64_TEMP%"
echo a3JuXEVjcCIgL2YgPm51bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9G >> "%PAYLOAD_B64_TEMP%"
echo RkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9u >> "%PAYLOAD_B64_TEMP%"
echo XENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cSW5mbyIgL3Yg >> "%PAYLOAD_B64_TEMP%"
echo Ikxhc3RId2YiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg >> "%PAYLOAD_B64_TEMP%"
echo L2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVn >> "%PAYLOAD_B64_TEMP%"
echo aW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cSW5mbyIgL3YgIkFjdGl2YXRpb25T >> "%PAYLOAD_B64_TEMP%"
echo dGF0ZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBP >> "%PAYLOAD_B64_TEMP%"
echo UFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNc >> "%PAYLOAD_B64_TEMP%"
echo MDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvIiAvdiAiQWN0aXZhdGlvblR5cGUi >> "%PAYLOAD_B64_TEMP%"
echo IC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0x >> "%PAYLOAD_B64_TEMP%"
echo DQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAw >> "%PAYLOAD_B64_TEMP%"
echo MDA2XHNldHRpbmdzXEVrcm5cSW5mbyIgL3YgIkxhc3RBY3RpdmF0aW9uRGF0ZSIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQg >> "%PAYLOAD_B64_TEMP%"
echo U2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAwMDZc >> "%PAYLOAD_B64_TEMP%"
echo c2V0dGluZ3NcRWtyblxJbmZvIiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBkZWxl >> "%PAYLOAD_B64_TEMP%"
echo dGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3Vy >> "%PAYLOAD_B64_TEMP%"
echo cmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAyMDBcc2V0dGluZ3Ncc3RQ >> "%PAYLOAD_B64_TEMP%"
echo cm90b2NvbEZpbHRlcmluZ1xzdEFwcFNzbCIgL3YgInVSb290Q3JlYXRlVGltZSIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQg >> "%PAYLOAD_B64_TEMP%"
echo U2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAyMDBc >> "%PAYLOAD_B64_TEMP%"
echo c2V0dGluZ3Ncc3RQcm90b2NvbEZpbHRlcmluZ1xzdEFwcFNzbCIgL2YgPm51bCAy >> "%PAYLOAD_B64_TEMP%"
echo PiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNF >> "%PAYLOAD_B64_TEMP%"
echo VFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXFBsdWdpbnNcMDEwMDA0MDBc >> "%PAYLOAD_B64_TEMP%"
echo Q29uZmlnQmFja3VwIiAvdiAiVXNlcm5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXFBsdWdpbnNcMDEwMDA0MDBcQ29uZmlnQmFja3VwIiAvdiAiUGFzc3dv >> "%PAYLOAD_B64_TEMP%"
echo cmQiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BT >> "%PAYLOAD_B64_TEMP%"
echo Kz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNF >> "%PAYLOAD_B64_TEMP%"
echo VFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXFBsdWdpbnNcMDEwMDA0MDBc >> "%PAYLOAD_B64_TEMP%"
echo Q29uZmlnQmFja3VwIiAvdiAiTGVnYWN5VXNlcm5hbWUiIC9mID5udWwgMj4mMQ0K >> "%PAYLOAD_B64_TEMP%"
echo aWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVs >> "%PAYLOAD_B64_TEMP%"
echo ZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1 >> "%PAYLOAD_B64_TEMP%"
echo cnJlbnRWZXJzaW9uXFBsdWdpbnNcMDEwMDA0MDBcQ29uZmlnQmFja3VwIiAvdiAi >> "%PAYLOAD_B64_TEMP%"
echo TGVnYWN5UGFzc3dvcmQiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwg >> "%PAYLOAD_B64_TEMP%"
echo MSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJTkVfU09G >> "%PAYLOAD_B64_TEMP%"
echo VFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXFBsdWdpbnNc >> "%PAYLOAD_B64_TEMP%"
echo MDEwMDA0MDBcQ29uZmlnQmFja3VwIiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBk >> "%PAYLOAD_B64_TEMP%"
echo ZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlc >> "%PAYLOAD_B64_TEMP%"
echo Q3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDA0MDBcc2V0dGluZ3Mi >> "%PAYLOAD_B64_TEMP%"
echo IC92ICJQYXNzd29yZCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo IHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9T >> "%PAYLOAD_B64_TEMP%"
echo T0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmln >> "%PAYLOAD_B64_TEMP%"
echo XHBsdWdpbnNcMDEwMDA0MDBcc2V0dGluZ3MiIC92ICJVc2VybmFtZSIgL2YgPm51 >> "%PAYLOAD_B64_TEMP%"
echo bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVn >> "%PAYLOAD_B64_TEMP%"
echo LmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJp >> "%PAYLOAD_B64_TEMP%"
echo dHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDA0MDBcc2V0dGlu >> "%PAYLOAD_B64_TEMP%"
echo Z3MiIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5F >> "%PAYLOAD_B64_TEMP%"
echo X1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25m >> "%PAYLOAD_B64_TEMP%"
echo aWdccGx1Z2luc1wwMTAwMDYwMFxzZXR0aW5nc1xEaXN0UGFja2FnZVxBcHBTZXR0 >> "%PAYLOAD_B64_TEMP%"
echo aW5ncyIgL3YgIkFjdE9wdGlvbnMiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9y >> "%PAYLOAD_B64_TEMP%"
echo bGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENv >> "%PAYLOAD_B64_TEMP%"
echo bmZpZ1xwbHVnaW5zXDAxMDAwNjAwXHNldHRpbmdzXERpc3RQYWNrYWdlXEFwcFNl >> "%PAYLOAD_B64_TEMP%"
echo dHRpbmdzIiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZG >> "%PAYLOAD_B64_TEMP%"
echo TElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25c >> "%PAYLOAD_B64_TEMP%"
echo Q29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvXExhc3RI >> "%PAYLOAD_B64_TEMP%"
echo d0luZm8iIC92ICJDb21wdXRlck5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVy >> "%PAYLOAD_B64_TEMP%"
echo cm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xN >> "%PAYLOAD_B64_TEMP%"
echo XE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJz >> "%PAYLOAD_B64_TEMP%"
echo aW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cSW5mb1xM >> "%PAYLOAD_B64_TEMP%"
echo YXN0SHdJbmZvIiAvdiAiVmVyc2lvbiIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJy >> "%PAYLOAD_B64_TEMP%"
echo b3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZG >> "%PAYLOAD_B64_TEMP%"
echo TElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25c >> "%PAYLOAD_B64_TEMP%"
echo Q29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvXExhc3RI >> "%PAYLOAD_B64_TEMP%"
echo d0luZm8iIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZM >> "%PAYLOAD_B64_TEMP%"
echo SU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJ >> "%PAYLOAD_B64_TEMP%"
echo bmZvIiAvdiAiRWRpdGlvbk5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9y >> "%PAYLOAD_B64_TEMP%"
echo bGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9G >> "%PAYLOAD_B64_TEMP%"
echo RkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9u >> "%PAYLOAD_B64_TEMP%"
echo XEluZm8iIC92ICJGdWxsUHJvZHVjdE5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90 >> "%PAYLOAD_B64_TEMP%"
echo IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXEluZm8iIC92ICJJbnN0YWxsZWRCeUVSQSIgL2YgPm51bCAyPiYxDQpp >> "%PAYLOAD_B64_TEMP%"
echo ZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxl >> "%PAYLOAD_B64_TEMP%"
echo dGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3Vy >> "%PAYLOAD_B64_TEMP%"
echo cmVudFZlcnNpb25cSW5mbyIgL3YgIkFjdGl2ZUZlYXR1cmVzIiAvZiA+bnVsIDI+ >> "%PAYLOAD_B64_TEMP%"
echo JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhl >> "%PAYLOAD_B64_TEMP%"
echo IGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0 >> "%PAYLOAD_B64_TEMP%"
echo eVxDdXJyZW50VmVyc2lvblxJbmZvIiAvdiAiVW5pcXVlSWQiIC9mID5udWwgMj4m >> "%PAYLOAD_B64_TEMP%"
echo MQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUg >> "%PAYLOAD_B64_TEMP%"
echo ZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5 >> "%PAYLOAD_B64_TEMP%"
echo XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJXZWJBY3RpdmF0aW9uU3RhdGUiIC9m >> "%PAYLOAD_B64_TEMP%"
echo ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoN >> "%PAYLOAD_B64_TEMP%"
echo ClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo IFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJXZWJTZWF0SWQiIC9m >> "%PAYLOAD_B64_TEMP%"
echo ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoN >> "%PAYLOAD_B64_TEMP%"
echo ClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo IFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJXZWJDbGllbnRDb21w >> "%PAYLOAD_B64_TEMP%"
echo dXRlck5hbWUiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQg >> "%PAYLOAD_B64_TEMP%"
echo L2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92ICJX >> "%PAYLOAD_B64_TEMP%"
echo ZWJMaWNlbnNlUHVibGljSWQiIC9mID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2 >> "%PAYLOAD_B64_TEMP%"
echo ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXElu >> "%PAYLOAD_B64_TEMP%"
echo Zm8iIC92ICJMYXN0QWN0aXZhdGlvblJlc3VsdCIgL2YgPm51bCAyPiYxDQppZiBu >> "%PAYLOAD_B64_TEMP%"
echo b3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhL >> "%PAYLOAD_B64_TEMP%"
echo TE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZl >> "%PAYLOAD_B64_TEMP%"
echo cnNpb25cSW5mbyIgL2YgPm51bCAyPiYxDQoNCmNhbGwgOkxvZyAiUmVnaXN0cnkg >> "%PAYLOAD_B64_TEMP%"
echo bW9kaWZpY2F0aW9ucyBjb21wbGV0ZSAtIFN1Y2Nlc3NmdWxseSBkZWxldGVkICVP >> "%PAYLOAD_B64_TEMP%"
echo UFMlIHZhbHVlcyINCg0KOjogVW5sb2FkIHRoZSBoaXZlDQpjYWxsIDpMb2cgIlVu >> "%PAYLOAD_B64_TEMP%"
echo bG9hZGluZyBTT0ZUV0FSRSBoaXZlLi4uIg0KcmVnIHVubG9hZCBIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkUgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICAgIGNh >> "%PAYLOAD_B64_TEMP%"
echo bGwgOkxvZyAiW1dBUk5dIEZhaWxlZCB0byB1bmxvYWQgaGl2ZSBvbiBmaXJzdCBh >> "%PAYLOAD_B64_TEMP%"
echo dHRlbXB0LCByZXRyeWluZy4uLiINCiAgICB0aW1lb3V0IC90IDMgL25vYnJlYWsg >> "%PAYLOAD_B64_TEMP%"
echo Pm51bA0KICAgIHJlZyB1bmxvYWQgSEtMTVxPRkZMSU5FX1NPRlRXQVJFID5udWwg >> "%PAYLOAD_B64_TEMP%"
echo Mj4mMQ0KICAgIGlmIGVycm9ybGV2ZWwgMSAoDQogICAgICAgIGNhbGwgOkxvZyAi >> "%PAYLOAD_B64_TEMP%"
echo W0VSUk9SXSBGYWlsZWQgdG8gdW5sb2FkIGhpdmUgYWZ0ZXIgcmV0cnkgLSB3aWxs >> "%PAYLOAD_B64_TEMP%"
echo IHJlbWFpbiBsb2FkZWQgdW50aWwgcmVzdGFydCINCiAgICApIGVsc2UgKA0KICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICBjYWxsIDpMb2cgIkhpdmUgdW5sb2FkZWQgc3VjY2Vzc2Z1bGx5IG9uIHJl >> "%PAYLOAD_B64_TEMP%"
echo dHJ5Ig0KICAgICkNCikgZWxzZSAoDQogICAgY2FsbCA6TG9nICJIaXZlIHVubG9h >> "%PAYLOAD_B64_TEMP%"
echo ZGVkIHN1Y2Nlc3NmdWxseSINCikNCg0KY2FsbCA6TG9nICJTVUNDRVNTOiBFU0VU >> "%PAYLOAD_B64_TEMP%"
echo LVJlc2V0IGNvbXBsZXRlIg0KY2FsbCA6TG9nICJUYXJnZXQgc3lzdGVtOiAlV0lO >> "%PAYLOAD_B64_TEMP%"
echo RElSJSINCmNhbGwgOkxvZyAiUmVnaXN0cnkgdmFsdWVzIGRlbGV0ZWQ6ICVPUFMl >> "%PAYLOAD_B64_TEMP%"
echo Ig0KY2FsbCA6TG9nICJOT1RFOiBFU0VUIHdpbGwgbmVlZCB0byBiZSByZWFjdGl2 >> "%PAYLOAD_B64_TEMP%"
echo YXRlZCB3aGVuIFdpbmRvd3MgYm9vdHMiDQoNCjo6IENyZWF0ZSB0aGUgMS1zZWNv >> "%PAYLOAD_B64_TEMP%"
echo bmQgc2xlZXAgdXRpbGl0eQ0KZWNobyBXU2NyaXB0LlNsZWVwIDEwMDAgPiIlVEVN >> "%PAYLOAD_B64_TEMP%"
echo UCVccy52YnMiDQoNCmVjaG8uDQplY2hvID09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09DQplY2hvICAgICAgICAgIEVTRVQgUkVTRVQg >> "%PAYLOAD_B64_TEMP%"
echo Q09NUExFVEVEDQplY2hvID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09DQplY2hvLg0KZWNobyBUYXJnZXQgU3lzdGVtOiAlV0lORElS >> "%PAYLOAD_B64_TEMP%"
echo JQ0KZWNobyBSZWdpc3RyeSBWYWx1ZXMgRGVsZXRlZDogJU9QUyUNCmVjaG8uDQpl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIEVTRVQgd2lsbCBuZWVkIHRvIGJlIHJlYWN0aXZhdGVkIHdoZW4gV2luZG93 >> "%PAYLOAD_B64_TEMP%"
echo cyBib290cy4NCmVjaG8uDQplY2hvIFdpbGwgcmVib290IGluIDcgc2Vjb25kcy4u >> "%PAYLOAD_B64_TEMP%"
echo Lg0KDQo6OiBTaWxlbnQgY291bnRkb3duDQpmb3IgL0wgJSVpIGluICg3LC0xLDEp >> "%PAYLOAD_B64_TEMP%"
echo IGRvICgNCiAgICBjc2NyaXB0IC8vbm9sb2dvICIlVEVNUCVccy52YnMiDQopDQoN >> "%PAYLOAD_B64_TEMP%"
echo CmVjaG8uDQplY2hvIFJlYm9vdGluZyBub3cuLi4NCmNhbGwgOkxvZyAiSW5pdGlh >> "%PAYLOAD_B64_TEMP%"
echo dGluZyBzeXN0ZW0gcmVib290Li4uIg0KDQo6OiBGaW5hbCBkdW1wIGJlZm9yZSBy >> "%PAYLOAD_B64_TEMP%"
echo ZWJvb3QNCmNhbGwgOkR1bXBUZW1wTG9nDQoNCndwZXV0aWwgcmVib290DQpnb3Rv >> "%PAYLOAD_B64_TEMP%"
echo IDpFbmRTY3JpcHQNCg0KOjogU0lNUExJRklFRCBGVU5DVElPTlMNCg0KOkxvZw0K >> "%PAYLOAD_B64_TEMP%"
echo c2V0ICJsb2d0ZXh0PSUqIg0Kc2V0ICJsb2d0ZXh0PSFsb2d0ZXh0OiI9ISINCmVj >> "%PAYLOAD_B64_TEMP%"
echo aG8gIWxvZ3RleHQhDQppZiBkZWZpbmVkIE1BSU5fTE9HRklMRSAoDQogICAgZWNo >> "%PAYLOAD_B64_TEMP%"
echo byBbJWRhdGUlICV0aW1lJV0gIWxvZ3RleHQhPj4iJU1BSU5fTE9HRklMRSUiIDI+ >> "%PAYLOAD_B64_TEMP%"
echo bnVsDQopIGVsc2UgKA0KICAgIGVjaG8gWyVkYXRlJSAldGltZSVdICFsb2d0ZXh0 >> "%PAYLOAD_B64_TEMP%"
echo IT4+IiVURU1QX0xPR0ZJTEUlIg0KKQ0KZ290byA6ZW9mDQoNCjpTZXR1cE1haW5M >> "%PAYLOAD_B64_TEMP%"
echo b2dnaW5nIA0KOjogR2V0IGxvZyBwYXRoIGZyb20gcmVnaXN0cnkgYW5kIHNldCB1 >> "%PAYLOAD_B64_TEMP%"
echo cCBtYWluIGxvZyBmaWxlDQpzZXQgIkxPR19QQVRIPSINCmZvciAvZiAidG9rZW5z >> "%PAYLOAD_B64_TEMP%"
echo PTIsKiIgJSVBIGluICgncmVnIHF1ZXJ5ICJIS0xNXE9GRkxJTkVfU09GVFdBUkVc >> "%PAYLOAD_B64_TEMP%"
echo RVNFVFJlc2V0IiAvdiBMb2dQYXRoIDJePm51bCBefCBmaW5kICJSRUdfU1oiJykg >> "%PAYLOAD_B64_TEMP%"
echo ZG8gc2V0ICJMT0dfUEFUSD0lJUIiDQoNCmlmIGRlZmluZWQgTE9HX1BBVEggKA0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgIGNhbGwgOkxvZyAiTG9nIHBhdGggZm91bmQ6ICVMT0dfUEFUSCUiDQogICAg >> "%PAYLOAD_B64_TEMP%"
echo DQogICAgOjogRml4IHRoZSBwYXRoIG1hcHBpbmcgLSByZXBsYWNlIEM6IHdpdGgg >> "%PAYLOAD_B64_TEMP%"
echo ZGV0ZWN0ZWQgZHJpdmUNCiAgICBzZXQgIk1BSU5fTE9HRklMRT0lV0lORFJJVkUl >> "%PAYLOAD_B64_TEMP%"
echo JUxPR19QQVRIOn4yJSINCiAgICANCiAgICBjYWxsIDpMb2cgIk1hcHBlZCB0byBX >> "%PAYLOAD_B64_TEMP%"
echo aW5SRSBwYXRoOiAlTUFJTl9MT0dGSUxFJSINCiAgICANCiAgICA6OiBEbyBpbml0 >> "%PAYLOAD_B64_TEMP%"
echo aWFsIGR1bXANCiAgICBjYWxsIDpEdW1wVGVtcExvZw0KICAgIGNhbGwgOkxvZyAi >> "%PAYLOAD_B64_TEMP%"
echo Q29udGludWVkIGZyb20gdGVtcCBsb2ciDQopIGVsc2UgKA0KICAgIGNhbGwgOkxv >> "%PAYLOAD_B64_TEMP%"
echo ZyAiW1dBUk5dIExvZyBwYXRoIG5vdCBmb3VuZCBpbiByZWdpc3RyeSwgY29udGlu >> "%PAYLOAD_B64_TEMP%"
echo dWluZyB3aXRoIHRlbXAgbG9nIG9ubHkiDQopDQpnb3RvIDplb2YNCg0KOkR1bXBU >> "%PAYLOAD_B64_TEMP%"
echo ZW1wTG9nDQo6OiBEdW1wIHRlbXAgbG9nIHRvIG1haW4gbG9nIGlmIHdlIGhhdmUg >> "%PAYLOAD_B64_TEMP%"
echo b25lDQppZiBkZWZpbmVkIE1BSU5fTE9HRklMRSAoDQogICAgaWYgZXhpc3QgIiVU >> "%PAYLOAD_B64_TEMP%"
echo RU1QX0xPR0ZJTEUlIiAoDQogICAgICAgIGVjaG8gWyVkYXRlJSAldGltZSVdID09 >> "%PAYLOAD_B64_TEMP%"
echo PSBEdW1waW5nIHRlbXAgbG9nIGNvbnRlbnRzID09PT4+IiVNQUlOX0xPR0ZJTEUl >> "%PAYLOAD_B64_TEMP%"
echo IiAyPm51bA0KICAgICAgICB0eXBlICIlVEVNUF9MT0dGSUxFJSI+PiIlTUFJTl9M >> "%PAYLOAD_B64_TEMP%"
echo T0dGSUxFJSIgMj5udWwNCiAgICAgICAgZWNobyBbJWRhdGUlICV0aW1lJV0gPT09 >> "%PAYLOAD_B64_TEMP%"
echo IEVuZCB0ZW1wIGxvZyBkdW1wID09PT4+IiVNQUlOX0xPR0ZJTEUlIiAyPm51bA0K >> "%PAYLOAD_B64_TEMP%"
echo ICAgICkNCikNCmdvdG8gOmVvZg0KDQo6RmF0YWxFcnJvcg0KZWNoby4NCmNhbGwg >> "%PAYLOAD_B64_TEMP%"
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
echo IHlvdSBwdWxsIGhpcyBvZmY/IFRoaXMgc2NyaXB0IHJlcXVpcmVzIFdJTkRPV1Mg >> "%PAYLOAD_B64_TEMP%"
echo dG8gYmUgaW5zdGFsbGVkLg0KZWNoby4NCg0KOjogQ291bnRkb3duIGJ5IHByaW50 >> "%PAYLOAD_B64_TEMP%"
echo aW5nIGEgbmV3IGxpbmUgZWFjaCBzZWNvbmQNCmZvciAvTCAlJWkgaW4gKDE1LC0x >> "%PAYLOAD_B64_TEMP%"
echo LDEpIGRvICgNCiAgICBlY2hvIFdJTkRPV1Mgbm90IGRldGVjdGVkLiBSZWJvb3Rp >> "%PAYLOAD_B64_TEMP%"
echo bmcgaW4gJSVpIHNlY29uZHMuLi4gUHJlc3MgQ3RybCtDIHRvIFJlYm9vdC4NCiAg >> "%PAYLOAD_B64_TEMP%"
echo ICBjc2NyaXB0IC8vbm9sb2dvICIlVEVNUCVccy52YnMiDQopDQoNCmVjaG8uDQpl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIFJlYm9vdGluZyBub3cuLi4NCmNhbGwgOkxvZyAiW0ZBVEFMXSAlKiINCndw >> "%PAYLOAD_B64_TEMP%"
echo ZXV0aWwgcmVib290DQpleGl0IC9iIDENCg0KOkVuZFNjcmlwdA0KY2FsbCA6TG9n >> "%PAYLOAD_B64_TEMP%"
echo ICI9PT09PT09PT09PT09PT09PSBXaW5SRSBTY3JpcHQgU2Vzc2lvbiBFbmRlZCA9 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PSINCjo6IEZpbmFsIGR1bXANCmNhbGwgOkR1bXBUZW1w >> "%PAYLOAD_B64_TEMP%"
echo TG9nDQpleGl0IC9iICVlcnJvcmxldmVsJQ== >> "%PAYLOAD_B64_TEMP%"
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
