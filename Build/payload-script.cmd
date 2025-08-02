@echo off
setlocal EnableDelayedExpansion
echo ESET Registry Reset Script for WinPE/WinRE
echo ==========================================
wpeutil CreateConsole >nul 2>&1

:: Simple logging setup - only need temp file
set TEMP_LOGFILE=X:\eset_reset.log
set MAIN_LOGFILE=
set NONINTERACTIVE=0

:: Capture WinPE shell log
if exist "X:\Windows\System32\winpeshl.log" (
    echo [%date% %time%] === WinPE Shell Log Contents ====>>"%TEMP_LOGFILE%"
    type "X:\Windows\System32\winpeshl.log">>"%TEMP_LOGFILE%" 2>nul
    echo [%date% %time%] === End WinPE Shell Log ===>>"%TEMP_LOGFILE%"
)

call :Log "=== WinRE Script Session Started ==="
call :Log "ESET Registry Reset Script for WinPE/WinRE"

:: Initialize variables
set WINDRIVE=
set WINDIR=

:: Scan for Windows installation
call :Log "Scanning for Windows installation..."

for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\Windows\System32\Config\SOFTWARE" (
        set WINDRIVE=%%D:
        set WINDIR=%%D:\Windows
        call :Log "Found Windows installation on: %%D:"
        goto :FoundInstallation
    )
)

call :Log "[FATAL] No Windows installation found"
call :NoWindowsWarning "No Windows installation found on any drive"
goto :EndScript

:FoundInstallation
call :Log "Selected Windows installation: %WINDIR%"

:: Delete ESET license file
call :Log "Deleting ESET license file..."
set LICENSEPATH=%WINDRIVE%\ProgramData\ESET\ESET Security\License\license.lf
if exist "%LICENSEPATH%" (
    attrib -r -h -s "%LICENSEPATH%" >nul 2>&1
    del /f "%LICENSEPATH%" >nul 2>&1
    if exist "%LICENSEPATH%" (
        call :Log "[WARN] Failed to delete license file"
    ) else (
        call :Log "License file deleted successfully"
    )
) else (
    call :Log "License file not found"
)

:: Load the SOFTWARE hive
call :Log "Loading offline SOFTWARE hive..."
reg load HKLM\OFFLINE_SOFTWARE "%WINDIR%\System32\Config\SOFTWARE" >nul 2>&1
if errorlevel 1 (
    call :FatalError "Failed to load SOFTWARE hive"
)
call :Log "SOFTWARE hive loaded successfully"

:: SIMPLIFIED: Get main log path and do initial dump
call :Log "Retrieving log path from registry..."
call :SetupMainLogging

:: Perform all registry operations
call :Log "Starting ESET registry modifications..."

:: Counter for operations
set OPS=0

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check" /v "CfgSeqNumberEsetAccGlobal" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check" /v "DNSTimerSec" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" /v "SeatID" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" /v "ComputerName" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" /v "Token" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" /v "LastHwf" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" /v "ActivationState" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" /v "ActivationType" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" /v "LastActivationDate" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000200\settings\stProtocolFiltering\stAppSsl" /v "uRootCreateTime" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000200\settings\stProtocolFiltering\stAppSsl" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" /v "Username" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" /v "Password" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" /v "LegacyUsername" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" /v "LegacyPassword" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings" /v "Password" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings" /v "Username" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000600\settings\DistPackage\AppSettings" /v "ActOptions" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000600\settings\DistPackage\AppSettings" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo" /v "ComputerName" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo" /v "Version" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo" /f >nul 2>&1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "EditionName" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "FullProductName" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "InstalledByERA" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "ActiveFeatures" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "UniqueId" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "WebActivationState" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "WebSeatId" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "WebClientComputerName" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "WebLicensePublicId" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe delete "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /v "LastActivationResult" /f >nul 2>&1
if not errorlevel 1 set /a OPS+=1

Reg.exe add "HKLM\OFFLINE_SOFTWARE\ESET\ESET Security\CurrentVersion\Info" /f >nul 2>&1

call :Log "Registry modifications complete - Successfully deleted %OPS% values"

:: Unload the hive
call :Log "Unloading SOFTWARE hive..."
reg unload HKLM\OFFLINE_SOFTWARE >nul 2>&1
if errorlevel 1 (
    call :Log "[WARN] Failed to unload hive on first attempt, retrying..."
    echo WScript.Sleep 3000 >"%TEMP%\s3.vbs"
    cscript //nologo "%TEMP%\s3.vbs"
    reg unload HKLM\OFFLINE_SOFTWARE >nul 2>&1
    if errorlevel 1 (
        call :Log "[ERROR] Failed to unload hive after retry - will remain loaded until restart"
    ) else (
        call :Log "Hive unloaded successfully on retry"
    )
) else (
    call :Log "Hive unloaded successfully"
)

call :Log "SUCCESS: ESET-Reset complete"
call :Log "Target system: %WINDIR%"
call :Log "Registry values deleted: %OPS%"
call :Log "NOTE: ESET will need to be reactivated when Windows boots"

:: Create the 1-second sleep utility
echo WScript.Sleep 1000 >"%TEMP%\s.vbs"

echo.
echo ============================================
echo          ESET RESET COMPLETED
echo ============================================
echo.
echo Target System: %WINDIR%
echo Registry Values Deleted: %OPS%
echo.
echo ESET will need to be reactivated when Windows boots.
echo.
echo Rebooting in 7 seconds...

:: Silent countdown
for /L %%i in (7,-1,1) do (
    cscript //nologo "%TEMP%\s.vbs"
)

echo.
echo Rebooting now...
call :Log "Initiating system reboot..."

wpeutil reboot
goto :EndScript

:: SIMPLIFIED FUNCTIONS

:Log
set "logtext=%*"
set "logtext=!logtext:"=!"
echo !logtext!
if defined MAIN_LOGFILE (
    echo [%date% %time%] !logtext!>>"%MAIN_LOGFILE%" 2>nul
) else (
    echo [%date% %time%] !logtext!>>"%TEMP_LOGFILE%"
)
goto :eof

:SetupMainLogging 
:: Get log path from registry and set up main log file
set "LOG_PATH="
for /f "tokens=2,*" %%A in ('reg query "HKLM\OFFLINE_SOFTWARE\ESETReset" /v LogPath 2^>nul ^| find "REG_SZ"') do set "LOG_PATH=%%B"

if defined LOG_PATH (
    call :Log "Log path found: %LOG_PATH%"
    
    :: Path mapping - replace C: with detected drive
    set "MAIN_LOGFILE=%WINDRIVE%%LOG_PATH:~2%"
    
    call :Log "Log Mapped to WinRE path: !MAIN_LOGFILE!"
    
    :: Do initial dump
    call :DumpTempLog
    call :Log "Continued from temp log"
) else (
    call :Log "[WARN] Log path not found in registry, continuing with temp log only"
)
goto :eof

:DumpTempLog
:: Dump temp log to main log if we have one
if defined MAIN_LOGFILE (
    if exist "%TEMP_LOGFILE%" (
        echo [%date% %time%] === Dumping temp log contents ===>>"%MAIN_LOGFILE%" 2>nul
        type "%TEMP_LOGFILE%">>"%MAIN_LOGFILE%" 2>nul
        echo [%date% %time%] === End temp log dump ===>>"%MAIN_LOGFILE%" 2>nul
    )
)
goto :eof

:FatalError
echo.
call :Log "[FATAL] %*"
echo.
if "%NONINTERACTIVE%"=="0" (
    echo An unrecoverable error occurred. Please check the log file for details.
    pause
)
goto :EndScript

:NoWindowsWarning
@echo off
setlocal EnableExtensions

:: Create the 1-second sleep utility
echo WScript.Sleep 1000 >"%TEMP%\s.vbs"

cls
color 4F
echo.
echo ============================================
echo WARNING: WINDOWS INSTALLATION NOT DETECTED
echo ============================================
echo.
echo %*
echo.
echo Hey man. How did you pull his off? This script requires WINDOWS to be installed.
echo.

:: Countdown by printing a new line each second
for /L %%i in (15,-1,1) do (
    echo WINDOWS not detected. Rebooting in %%i seconds... Press Ctrl+C to Reboot.
    cscript //nologo "%TEMP%\s.vbs"
)

echo.
echo Rebooting now...
call :Log "[FATAL] %*"
wpeutil reboot
exit /b 1

:EndScript
call :Log "================= WinRE Script Session Ended ================="
:: Final dump
call :DumpTempLog
exit /b %errorlevel%