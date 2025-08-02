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
echo BASE64_CONTENT_GOES_HERE >> "%PAYLOAD_B64_TEMP%"
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
