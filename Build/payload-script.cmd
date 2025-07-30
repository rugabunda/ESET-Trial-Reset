@echo off
setlocal EnableDelayedExpansion
echo ESET Registry Reset Script for WinPE/WinRE
echo ==========================================

:: Ensure we have a console window in WinRE
wpeutil CreateConsole >nul 2>&1

:: Initialize variables
set WINDRIVE=
set WINDIR=

:: Scan for Windows installation with ESET
echo Scanning for Windows installation with ESET...
echo.

for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\Program Files\ESET" (
        if exist "%%D:\Windows\System32\Config\SOFTWARE" (
            set WINDRIVE=%%D:
            set WINDIR=%%D:\Windows
            echo Found ESET installation on: %%D:
            goto :FoundInstallation
        )
    )
)

:: If not found in Program Files, check Program Files (x86)
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\Program Files (x86)\ESET" (
        if exist "%%D:\Windows\System32\Config\SOFTWARE" (
            set WINDRIVE=%%D:
            set WINDIR=%%D:\Windows
            echo Found ESET installation on: %%D: (x86)
            goto :FoundInstallation
        )
    )
)

:: Not found
echo ERROR: No Windows installation with ESET found!
echo.
echo Checked for ESET in:
echo - \Program Files\ESET\
echo - \Program Files (x86)\ESET\
echo.
pause
exit /b 1

:FoundInstallation
echo.
echo ==========================================
echo Selected Windows installation: %WINDIR%
echo ==========================================
echo.

:: Delete the license file
echo Deleting ESET license file...
set LICENSEPATH=%WINDRIVE%\ProgramData\ESET\ESET Security\License\license.lf
if exist "%LICENSEPATH%" (
    attrib -r -h -s "%LICENSEPATH%" >nul 2>&1
    del /f "%LICENSEPATH%" >nul 2>&1
    if exist "%LICENSEPATH%" (
        echo WARNING: Failed to delete license file
    ) else (
        echo License file deleted successfully.
    )
) else (
    echo License file not found.
)
echo.

:: Check if hive already loaded
reg query "HKLM\OFFLINE_SOFTWARE" >nul 2>&1
if not errorlevel 1 (
    echo WARNING: OFFLINE_SOFTWARE hive already loaded!
    echo Attempting to unload...
    reg unload HKLM\OFFLINE_SOFTWARE >nul 2>&1
    timeout /t 2 /nobreak >nul
)

:: Load the SOFTWARE hive
echo Loading offline SOFTWARE hive...
reg load HKLM\OFFLINE_SOFTWARE "%WINDIR%\System32\Config\SOFTWARE" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Failed to load SOFTWARE hive
    pause
    exit /b 1
)
echo SOFTWARE hive loaded successfully.
echo.

:: Perform all registry operations
echo Modifying ESET registry entries...

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

echo.
echo Registry modifications complete.
echo Successfully deleted: %OPS% values
echo.

:: Unload the hive
echo Unloading SOFTWARE hive...
reg unload HKLM\OFFLINE_SOFTWARE >nul 2>&1
if errorlevel 1 (
    echo WARNING: Failed to unload hive on first attempt.
    echo Retrying in 3 seconds...
    timeout /t 3 /nobreak >nul
    reg unload HKLM\OFFLINE_SOFTWARE >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Failed to unload hive after retry.
        echo The hive will remain loaded until system restart.
    ) else (
        echo Hive unloaded successfully on retry.
    )
) else (
    echo Hive unloaded successfully.
)

:: Restore original WinRE configuration
echo Restoring WinRE to normal state...
if exist "X:\Windows\System32\winpeshl.ini.backup" (
    copy "X:\Windows\System32\winpeshl.ini.backup" "X:\Windows\System32\winpeshl.ini" >nul 2>&1
    del "X:\Windows\System32\winpeshl.ini.backup" >nul 2>&1
    echo WinRE configuration restored from backup.
) else (
    echo [LaunchApp] > "X:\Windows\System32\winpeshl.ini"
    echo AppPath=X:\sources\recovery\recenv.exe >> "X:\Windows\System32\winpeshl.ini"
    echo Default WinRE configuration restored.
)

:: Create cleanup script to handle locked files
echo Creating cleanup script...
> "%TEMP%\_cleanup.cmd" (
    echo @echo off
    echo timeout /t 2 ^>nul
::    echo attrib -h -s -r "%SystemRoot%\System32\winpeshl.ini.backup" 2^>nul
::    echo del /f /q "%SystemRoot%\System32\winpeshl.ini.backup" 2^>nul
    echo del /f /q "%SystemRoot%\System32\Offline-Reset.cmd" 2^>nul
    echo del /f /q "%%~f0" 2^>nul
)

:: Launch cleanup script in background
start "" /min "%TEMP%\_cleanup.cmd"

echo.
echo ==========================================
echo SUCCESS: ESET-Reset complete.
echo ==========================================
echo Target system: %WINDIR%
echo Registry values deleted: %OPS%
echo ==========================================
echo.
echo NOTE: ESET will need to be reactivated when Windows boots.
echo.
echo Press any key to reboot or CTRL+C to cancel...
pause >nul
wpeutil reboot