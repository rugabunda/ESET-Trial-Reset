@echo off
setlocal enabledelayedexpansion

:: =================================================================
:: ESET Offline Reset Management Tool - v5.0 (Base64 Method)
:: =================================================================
:: Automates WinRE Reset with Base64 embedded payload
:: =================================================================

:: --- Configuration ---
set MOUNT_DIR=%SystemDrive%\WinRE_Mount
set PAYLOAD_FILENAME=Offline-Reset.cmd
set PAYLOAD_B64_TEMP=%TEMP%\payload.b64
set LOGFILE=%~dp0ESET_Reset_Tool.log
set PARENT_SCRIPT=%~f0

:: -----------------------------------------------------------------
:: UAC Check: Re-launch as Administrator if needed 
:: -----------------------------------------------------------------
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process '%~s0' -ArgumentList '%*' -Verb RunAs"
    exit /B
)

:gotAdmin
pushd "%~dp0"

:: -----------------------------------------------------------------
:: --disarm flag handler
:: -----------------------------------------------------------------
if /I "%~1"=="--disarm" (
    echo [INFO]  --disarm flag detected – running DISARM routine …
    set "NONINTERACTIVE=1"
    goto :disable_reset
)

:: -----------------------------------------------------------------
:: --arm flag handler
:: -----------------------------------------------------------------
if /I "%~1"=="--arm" (
    echo [INFO]  --arm flag detected – running ARM routine …
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
    echo [WARN] BitLocker is ENABLED on your system drive.
    echo.
    echo  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo  !!  You WILL LIKELY NEED your BitLocker Recovery Key to proceed  !!
    echo  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo.
    echo  Find your key at: https://account.microsoft.com/devices/recoverykey
    echo.
    pause
)

:menu
cls
echo =========================================
echo   ESET Offline Reset Management Tool
echo =========================================
echo.
echo  [1] ARM Auto-Reset on Next Reboot
echo  [2] DISARM Auto-Reset
echo  [3] Exit
echo.
choice /C 123 /N /M "Please select an option: "
if errorlevel 3 goto :eof
if errorlevel 2 goto :disable_reset
if errorlevel 1 goto :enable_reset

:: =================================================================
:enable_reset
cls
echo [INFO] Arming reset process... >> "%LOGFILE%"

:: Cleanup and prepare mount directory
call :cleanup_mount

echo.
echo ==========================================
echo IMPORTANT: Before proceeding, ensure that:
echo - No command prompt/terminal windows are open in %MOUNT_DIR%
echo - No Explorer windows are browsing %MOUNT_DIR%
echo - No files from %MOUNT_DIR% are open in any applications
echo ==========================================
echo.
echo If dismount fails, manually run these commands:
echo   reagentc /unmountre /path %MOUNT_DIR% /commit
echo   rmdir /s /q %MOUNT_DIR%
echo   dism /cleanup-wim
echo.
pause
:enable_reset_flag
echo.
echo --- ARMING Auto-Reset --- 
echo.
echo One moment... (see ESET_Reset_Tool.log for details)
echo [INFO] Extracting payload from base64... >> "%LOGFILE%"
call :extract_payload
if errorlevel 1 (
    echo [ERROR] Failed to extract payload. See log.
    goto end_error
)

echo [INFO] Mounting WinRE image... >> "%LOGFILE%"
reagentc /mountre /path "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to mount WinRE image. See log.
    goto end_error
)

echo [INFO] Backing up original winpeshl.ini... >> "%LOGFILE%"
if exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini" (
    copy "%MOUNT_DIR%\Windows\System32\winpeshl.ini" "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" >> "%LOGFILE%" 2>&1
)

echo [INFO] Injecting payload script... >> "%LOGFILE%"
copy "%TEMP%\%PAYLOAD_FILENAME%" "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%" >> "%LOGFILE%" 2>&1

echo [INFO] Configuring WinRE startup... >> "%LOGFILE%"
echo [LaunchApps] > "%MOUNT_DIR%\Windows\System32\winpeshl.ini"
echo %%SystemRoot%%\System32\cmd.exe, /c %%SystemRoot%%\System32\%PAYLOAD_FILENAME% >> "%MOUNT_DIR%\Windows\System32\winpeshl.ini"

echo [INFO] Committing and unmounting WinRE... >> "%LOGFILE%"
reagentc /unmountre /path "%MOUNT_DIR%" /commit >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to unmount WinRE. This usually means files are still open. >> "%LOGFILE%"
    echo.
    echo ERROR: Dismount failed. This usually means files are still open.
    echo Please close all applications and try these commands manually:
    echo.
    echo   reagentc /unmountre /path %MOUNT_DIR% /commit
    echo   rmdir /s /q %MOUNT_DIR%
    echo   dism /cleanup-wim
    echo.
    pause
    goto end_error
)

call :cleanup_mount
del "%TEMP%\%PAYLOAD_FILENAME%" >nul 2>&1

reagentc /boottore >> "%LOGFILE%" 2>&1
if errorlevel 1 ( echo [WARN] Could not set one-time boot to WinRE. See log. & goto end_error )

echo.
echo =================================================================
echo SUCCESS: The ESET reset is ARMED.
echo The script will run automatically the next time you restart.
echo =================================================================
echo.

if defined NONINTERACTIVE (
    echo [INFO] Non-interactive mode - automatic restart in 4 seconds... >> "%LOGFILE%"
    shutdown /r /t 4 /c "Rebooting into recovery mode for ESET reset..."
    goto :eof
)

choice /C YN /M "Do you want to reboot now?"
if errorlevel 2 goto :menu
if errorlevel 1 shutdown /r /t 4 /c "Rebooting into recovery mode for ESET reset..."
goto :eof

:: =================================================================
:disable_reset
cls
echo.
echo --- DISARMING Auto-Reset ---
echo.
echo One moment... (see ESET_Reset_Tool.log for details)
echo [INFO] Disarming reset process... >> "%LOGFILE%"
echo [INFO] Preparing mount directory... >> "%LOGFILE%"
if exist "%MOUNT_DIR%" (
    rd /s /q "%MOUNT_DIR%" 2>nul
    dism /cleanup-wim >> "%LOGFILE%" 2>&1
)
mkdir "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1

echo [INFO] Mounting WinRE image for cleaning... >> "%LOGFILE%"
reagentc /mountre /path "%MOUNT_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 ( 
    echo [ERROR] Failed to mount WinRE image. See log. 
    goto end_error 
)

if exist "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%" (
    echo [INFO] Removing payload script... >> "%LOGFILE%"
    del "%MOUNT_DIR%\Windows\System32\%PAYLOAD_FILENAME%"
)
if exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini" (
    echo [INFO] Removing startup override... >> "%LOGFILE%"
    del "%MOUNT_DIR%\Windows\System32\winpeshl.ini"
)
if exist "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" (
    echo [INFO] Restoring original winpeshl.ini... >> "%LOGFILE%"
    move /y "%MOUNT_DIR%\Windows\System32\winpeshl.ini.backup" "%MOUNT_DIR%\Windows\System32\winpeshl.ini" >> "%LOGFILE%" 2>&1
)

echo [INFO] Committing cleanup and unmounting WinRE... >> "%LOGFILE%"
reagentc /unmountre /path "%MOUNT_DIR%" /commit >> "%LOGFILE%" 2>&1

rd /s /q "%MOUNT_DIR%" 2>nul
dism /cleanup-wim >> "%LOGFILE%" 2>&1

echo.
echo =================================================================
echo SUCCESS: The ESET auto-reset is DISABLED.
echo WinRE has been restored to its default state.
echo All autorun entries have been removed.
echo =================================================================
echo.
goto end_success

:end_error
echo An error occurred. Please check ESET_Reset_Tool.log for details.
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
if exist "%MOUNT_DIR%" (
    echo [INFO] Removing existing mount directory... >> "%LOGFILE%"
    rmdir /s /q "%MOUNT_DIR%" 2>nul
    if exist "%MOUNT_DIR%" (
        echo [WARN] Could not remove mount directory, attempting cleanup... >> "%LOGFILE%"
        dism /cleanup-wim >> "%LOGFILE%" 2>&1
        rmdir /s /q "%MOUNT_DIR%" 2>nul
    )
)
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