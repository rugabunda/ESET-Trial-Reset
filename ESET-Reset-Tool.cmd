@echo off
setlocal enabledelayedexpansion

:: =================================================================
:: ESET Offline Reset Management Tool - v5.0 (Base64 Method)
:: =================================================================
:: Uses ReAgentC /mountre with Base64 embedded payload
:: =================================================================

:: --- Configuration ---
set MOUNT_DIR=%SystemDrive%\WinRE_Mount
set PAYLOAD_FILENAME=Offline-Reset.cmd
set PAYLOAD_B64_TEMP=%TEMP%\payload.b64
set LOGFILE=%~dp0ESET_Reset_Tool.log
set PARENT_SCRIPT=%~f0

:: --- UAC Check: Re-launch as Administrator if needed ---
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process '%~s0' -Verb RunAs"
    exit /B
)

:gotAdmin
pushd "%~dp0"
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
pause
goto :menu

:end_success
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
echo QGVjaG8gb2ZmDQpzZXRsb2NhbCBFbmFibGVEZWxheWVkRXhwYW5zaW9uDQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo IEVTRVQgUmVnaXN0cnkgUmVzZXQgU2NyaXB0IGZvciBXaW5QRS9XaW5SRQ0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo byA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCg0K >> "%PAYLOAD_B64_TEMP%"
echo OjogRW5zdXJlIHdlIGhhdmUgYSBjb25zb2xlIHdpbmRvdyBpbiBXaW5SRQ0Kd3Bl >> "%PAYLOAD_B64_TEMP%"
echo dXRpbCBDcmVhdGVDb25zb2xlID5udWwgMj4mMQ0KDQo6OiBJbml0aWFsaXplIHZh >> "%PAYLOAD_B64_TEMP%"
echo cmlhYmxlcw0Kc2V0IFdJTkRSSVZFPQ0Kc2V0IFdJTkRJUj0NCg0KOjogU2NhbiBm >> "%PAYLOAD_B64_TEMP%"
echo b3IgV2luZG93cyBpbnN0YWxsYXRpb24gd2l0aCBFU0VUDQplY2hvIFNjYW5uaW5n >> "%PAYLOAD_B64_TEMP%"
echo IGZvciBXaW5kb3dzIGluc3RhbGxhdGlvbiB3aXRoIEVTRVQuLi4NCmVjaG8uDQoN >> "%PAYLOAD_B64_TEMP%"
echo CmZvciAlJUQgaW4gKEMgRCBFIEYgRyBIIEkgSiBLIEwgTSBOIE8gUCBRIFIgUyBU >> "%PAYLOAD_B64_TEMP%"
echo IFUgViBXIFggWSBaKSBkbyAoDQogICAgaWYgZXhpc3QgIiUlRDpcUHJvZ3JhbSBG >> "%PAYLOAD_B64_TEMP%"
echo aWxlc1xFU0VUIiAoDQogICAgICAgIGlmIGV4aXN0ICIlJUQ6XFdpbmRvd3NcU3lz >> "%PAYLOAD_B64_TEMP%"
echo dGVtMzJcQ29uZmlnXFNPRlRXQVJFIiAoDQogICAgICAgICAgICBzZXQgV0lORFJJ >> "%PAYLOAD_B64_TEMP%"
echo VkU9JSVEOg0KICAgICAgICAgICAgc2V0IFdJTkRJUj0lJUQ6XFdpbmRvd3MNCiAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICAgICAgIGVjaG8gRm91bmQgRVNFVCBpbnN0YWxsYXRpb24gb246ICUlRDoN >> "%PAYLOAD_B64_TEMP%"
echo CiAgICAgICAgICAgIGdvdG8gOkZvdW5kSW5zdGFsbGF0aW9uDQogICAgICAgICkN >> "%PAYLOAD_B64_TEMP%"
echo CiAgICApDQopDQoNCjo6IElmIG5vdCBmb3VuZCBpbiBQcm9ncmFtIEZpbGVzLCBj >> "%PAYLOAD_B64_TEMP%"
echo aGVjayBQcm9ncmFtIEZpbGVzICh4ODYpDQpmb3IgJSVEIGluIChDIEQgRSBGIEcg >> "%PAYLOAD_B64_TEMP%"
echo SCBJIEogSyBMIE0gTiBPIFAgUSBSIFMgVCBVIFYgVyBYIFkgWikgZG8gKA0KICAg >> "%PAYLOAD_B64_TEMP%"
echo IGlmIGV4aXN0ICIlJUQ6XFByb2dyYW0gRmlsZXMgKHg4NilcRVNFVCIgKA0KICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICBpZiBleGlzdCAiJSVEOlxXaW5kb3dzXFN5c3RlbTMyXENvbmZpZ1xTT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRSIgKA0KICAgICAgICAgICAgc2V0IFdJTkRSSVZFPSUlRDoNCiAgICAgICAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgIHNldCBXSU5ESVI9JSVEOlxXaW5kb3dzDQogICAgICAgICAgICBlY2hvIEZv >> "%PAYLOAD_B64_TEMP%"
echo dW5kIEVTRVQgaW5zdGFsbGF0aW9uIG9uOiAlJUQ6ICh4ODYpDQogICAgICAgICAg >> "%PAYLOAD_B64_TEMP%"
echo ICBnb3RvIDpGb3VuZEluc3RhbGxhdGlvbg0KICAgICAgICApDQogICAgKQ0KKQ0K >> "%PAYLOAD_B64_TEMP%"
echo DQo6OiBOb3QgZm91bmQNCmVjaG8gRVJST1I6IE5vIFdpbmRvd3MgaW5zdGFsbGF0 >> "%PAYLOAD_B64_TEMP%"
echo aW9uIHdpdGggRVNFVCBmb3VuZCENCmVjaG8uDQplY2hvIENoZWNrZWQgZm9yIEVT >> "%PAYLOAD_B64_TEMP%"
echo RVQgaW46DQplY2hvIC0gXFByb2dyYW0gRmlsZXNcRVNFVFwNCmVjaG8gLSBcUHJv >> "%PAYLOAD_B64_TEMP%"
echo Z3JhbSBGaWxlcyAoeDg2KVxFU0VUXA0KZWNoby4NCnBhdXNlDQpleGl0IC9iIDEN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KOkZvdW5kSW5zdGFsbGF0aW9uDQplY2hvLg0KZWNobyA9PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0NCmVjaG8gU2VsZWN0ZWQgV2lu >> "%PAYLOAD_B64_TEMP%"
echo ZG93cyBpbnN0YWxsYXRpb246ICVXSU5ESVIlDQplY2hvID09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09PT09PT09PT09PT09PQ0KZWNoby4NCg0KOjogRGVsZXRl >> "%PAYLOAD_B64_TEMP%"
echo IHRoZSBsaWNlbnNlIGZpbGUNCmVjaG8gRGVsZXRpbmcgRVNFVCBsaWNlbnNlIGZp >> "%PAYLOAD_B64_TEMP%"
echo bGUuLi4NCnNldCBMSUNFTlNFUEFUSD0lV0lORFJJVkUlXFByb2dyYW1EYXRhXEVT >> "%PAYLOAD_B64_TEMP%"
echo RVRcRVNFVCBTZWN1cml0eVxMaWNlbnNlXGxpY2Vuc2UubGYNCmlmIGV4aXN0ICIl >> "%PAYLOAD_B64_TEMP%"
echo TElDRU5TRVBBVEglIiAoDQogICAgYXR0cmliIC1yIC1oIC1zICIlTElDRU5TRVBB >> "%PAYLOAD_B64_TEMP%"
echo VEglIiA+bnVsIDI+JjENCiAgICBkZWwgL2YgIiVMSUNFTlNFUEFUSCUiID5udWwg >> "%PAYLOAD_B64_TEMP%"
echo Mj4mMQ0KICAgIGlmIGV4aXN0ICIlTElDRU5TRVBBVEglIiAoDQogICAgICAgIGVj >> "%PAYLOAD_B64_TEMP%"
echo aG8gV0FSTklORzogRmFpbGVkIHRvIGRlbGV0ZSBsaWNlbnNlIGZpbGUNCiAgICAp >> "%PAYLOAD_B64_TEMP%"
echo IGVsc2UgKA0KICAgICAgICBlY2hvIExpY2Vuc2UgZmlsZSBkZWxldGVkIHN1Y2Nl >> "%PAYLOAD_B64_TEMP%"
echo c3NmdWxseS4NCiAgICApDQopIGVsc2UgKA0KICAgIGVjaG8gTGljZW5zZSBmaWxl >> "%PAYLOAD_B64_TEMP%"
echo IG5vdCBmb3VuZC4NCikNCmVjaG8uDQoNCjo6IENoZWNrIGlmIGhpdmUgYWxyZWFk >> "%PAYLOAD_B64_TEMP%"
echo eSBsb2FkZWQNCnJlZyBxdWVyeSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFIiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gV0FSTklORzog >> "%PAYLOAD_B64_TEMP%"
echo T0ZGTElORV9TT0ZUV0FSRSBoaXZlIGFscmVhZHkgbG9hZGVkIQ0KICAgIGVjaG8g >> "%PAYLOAD_B64_TEMP%"
echo QXR0ZW1wdGluZyB0byB1bmxvYWQuLi4NCiAgICByZWcgdW5sb2FkIEhLTE1cT0ZG >> "%PAYLOAD_B64_TEMP%"
echo TElORV9TT0ZUV0FSRSA+bnVsIDI+JjENCiAgICB0aW1lb3V0IC90IDIgL25vYnJl >> "%PAYLOAD_B64_TEMP%"
echo YWsgPm51bA0KKQ0KDQo6OiBMb2FkIHRoZSBTT0ZUV0FSRSBoaXZlDQplY2hvIExv >> "%PAYLOAD_B64_TEMP%"
echo YWRpbmcgb2ZmbGluZSBTT0ZUV0FSRSBoaXZlLi4uDQpyZWcgbG9hZCBIS0xNXE9G >> "%PAYLOAD_B64_TEMP%"
echo RkxJTkVfU09GVFdBUkUgIiVXSU5ESVIlXFN5c3RlbTMyXENvbmZpZ1xTT0ZUV0FS >> "%PAYLOAD_B64_TEMP%"
echo RSIgPm51bCAyPiYxDQppZiBlcnJvcmxldmVsIDEgKA0KICAgIGVjaG8gRVJST1I6 >> "%PAYLOAD_B64_TEMP%"
echo IEZhaWxlZCB0byBsb2FkIFNPRlRXQVJFIGhpdmUNCiAgICBwYXVzZQ0KICAgIGV4 >> "%PAYLOAD_B64_TEMP%"
echo aXQgL2IgMQ0KKQ0KZWNobyBTT0ZUV0FSRSBoaXZlIGxvYWRlZCBzdWNjZXNzZnVs >> "%PAYLOAD_B64_TEMP%"
echo bHkuDQplY2hvLg0KDQo6OiBQZXJmb3JtIGFsbCByZWdpc3RyeSBvcGVyYXRpb25z >> "%PAYLOAD_B64_TEMP%"
echo DQplY2hvIE1vZGlmeWluZyBFU0VUIHJlZ2lzdHJ5IGVudHJpZXMuLi4NCg0KOjog >> "%PAYLOAD_B64_TEMP%"
echo Q291bnRlciBmb3Igb3BlcmF0aW9ucw0Kc2V0IE9QUz0wDQoNClJlZy5leGUgZGVs >> "%PAYLOAD_B64_TEMP%"
echo ZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1 >> "%PAYLOAD_B64_TEMP%"
echo cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVr >> "%PAYLOAD_B64_TEMP%"
echo cm5cQ2hlY2siIC92ICJDZmdTZXFOdW1iZXJFc2V0QWNjR2xvYmFsIiAvZiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1 >> "%PAYLOAD_B64_TEMP%"
echo cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0 >> "%PAYLOAD_B64_TEMP%"
echo aW5nc1xFa3JuXENoZWNrIiAvdiAiRE5TVGltZXJTZWMiIC9mID5udWwgMj4mMQ0K >> "%PAYLOAD_B64_TEMP%"
echo aWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRk >> "%PAYLOAD_B64_TEMP%"
echo ICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJl >> "%PAYLOAD_B64_TEMP%"
echo bnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5c >> "%PAYLOAD_B64_TEMP%"
echo Q2hlY2siIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZM >> "%PAYLOAD_B64_TEMP%"
echo SU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxD >> "%PAYLOAD_B64_TEMP%"
echo b25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEVjcCIgL3YgIlNl >> "%PAYLOAD_B64_TEMP%"
echo YXRJRCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBP >> "%PAYLOAD_B64_TEMP%"
echo UFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNc >> "%PAYLOAD_B64_TEMP%"
echo MDEwMDAwMDZcc2V0dGluZ3NcRWtyblxFY3AiIC92ICJDb21wdXRlck5hbWUiIC9m >> "%PAYLOAD_B64_TEMP%"
echo ID5udWwgMj4mMQ0KaWYgbm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoN >> "%PAYLOAD_B64_TEMP%"
echo ClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo IFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2 >> "%PAYLOAD_B64_TEMP%"
echo XHNldHRpbmdzXEVrcm5cRWNwIiAvdiAiVG9rZW4iIC9mID5udWwgMj4mMQ0KaWYg >> "%PAYLOAD_B64_TEMP%"
echo bm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgYWRkICJI >> "%PAYLOAD_B64_TEMP%"
echo S0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRW >> "%PAYLOAD_B64_TEMP%"
echo ZXJzaW9uXENvbmZpZ1xwbHVnaW5zXDAxMDAwMDA2XHNldHRpbmdzXEVrcm5cRWNw >> "%PAYLOAD_B64_TEMP%"
echo IiAvZiA+bnVsIDI+JjENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9T >> "%PAYLOAD_B64_TEMP%"
echo T0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmln >> "%PAYLOAD_B64_TEMP%"
echo XHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvIiAvdiAiTGFzdEh3 >> "%PAYLOAD_B64_TEMP%"
echo ZiIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMr >> "%PAYLOAD_B64_TEMP%"
echo PTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEw >> "%PAYLOAD_B64_TEMP%"
echo MDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvIiAvdiAiQWN0aXZhdGlvblN0YXRlIiAv >> "%PAYLOAD_B64_TEMP%"
echo ZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0K >> "%PAYLOAD_B64_TEMP%"
echo DQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNF >> "%PAYLOAD_B64_TEMP%"
echo VCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAw >> "%PAYLOAD_B64_TEMP%"
echo NlxzZXR0aW5nc1xFa3JuXEluZm8iIC92ICJBY3RpdmF0aW9uVHlwZSIgL2YgPm51 >> "%PAYLOAD_B64_TEMP%"
echo bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVn >> "%PAYLOAD_B64_TEMP%"
echo LmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2Vj >> "%PAYLOAD_B64_TEMP%"
echo dXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0 >> "%PAYLOAD_B64_TEMP%"
echo dGluZ3NcRWtyblxJbmZvIiAvdiAiTGFzdEFjdGl2YXRpb25EYXRlIiAvZiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0 >> "%PAYLOAD_B64_TEMP%"
echo eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5n >> "%PAYLOAD_B64_TEMP%"
echo c1xFa3JuXEluZm8iIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtM >> "%PAYLOAD_B64_TEMP%"
echo TVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVy >> "%PAYLOAD_B64_TEMP%"
echo c2lvblxDb25maWdccGx1Z2luc1wwMTAwMDIwMFxzZXR0aW5nc1xzdFByb3RvY29s >> "%PAYLOAD_B64_TEMP%"
echo RmlsdGVyaW5nXHN0QXBwU3NsIiAvdiAidVJvb3RDcmVhdGVUaW1lIiAvZiA+bnVs >> "%PAYLOAD_B64_TEMP%"
echo IDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcu >> "%PAYLOAD_B64_TEMP%"
echo ZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0 >> "%PAYLOAD_B64_TEMP%"
echo eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDIwMFxzZXR0aW5n >> "%PAYLOAD_B64_TEMP%"
echo c1xzdFByb3RvY29sRmlsdGVyaW5nXHN0QXBwU3NsIiAvZiA+bnVsIDI+JjENCg0K >> "%PAYLOAD_B64_TEMP%"
echo UmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQg >> "%PAYLOAD_B64_TEMP%"
echo U2VjdXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdC >> "%PAYLOAD_B64_TEMP%"
echo YWNrdXAiIC92ICJVc2VybmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3Js >> "%PAYLOAD_B64_TEMP%"
echo ZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZG >> "%PAYLOAD_B64_TEMP%"
echo TElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25c >> "%PAYLOAD_B64_TEMP%"
echo UGx1Z2luc1wwMTAwMDQwMFxDb25maWdCYWNrdXAiIC92ICJQYXNzd29yZCIgL2Yg >> "%PAYLOAD_B64_TEMP%"
echo Pm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0K >> "%PAYLOAD_B64_TEMP%"
echo UmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQg >> "%PAYLOAD_B64_TEMP%"
echo U2VjdXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdC >> "%PAYLOAD_B64_TEMP%"
echo YWNrdXAiIC92ICJMZWdhY3lVc2VybmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3Qg >> "%PAYLOAD_B64_TEMP%"
echo ZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhL >> "%PAYLOAD_B64_TEMP%"
echo TE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZl >> "%PAYLOAD_B64_TEMP%"
echo cnNpb25cUGx1Z2luc1wwMTAwMDQwMFxDb25maWdCYWNrdXAiIC92ICJMZWdhY3lQ >> "%PAYLOAD_B64_TEMP%"
echo YXNzd29yZCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAv >> "%PAYLOAD_B64_TEMP%"
echo YSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxF >> "%PAYLOAD_B64_TEMP%"
echo U0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cUGx1Z2luc1wwMTAwMDQw >> "%PAYLOAD_B64_TEMP%"
echo MFxDb25maWdCYWNrdXAiIC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAi >> "%PAYLOAD_B64_TEMP%"
echo SEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50 >> "%PAYLOAD_B64_TEMP%"
echo VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDQwMFxzZXR0aW5ncyIgL3YgIlBh >> "%PAYLOAD_B64_TEMP%"
echo c3N3b3JkIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9h >> "%PAYLOAD_B64_TEMP%"
echo IE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NPRlRXQVJF >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdccGx1Z2lu >> "%PAYLOAD_B64_TEMP%"
echo c1wwMTAwMDQwMFxzZXR0aW5ncyIgL3YgIlVzZXJuYW1lIiAvZiA+bnVsIDI+JjEN >> "%PAYLOAD_B64_TEMP%"
echo CmlmIG5vdCBlcnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFk >> "%PAYLOAD_B64_TEMP%"
echo ZCAiSEtMTVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJy >> "%PAYLOAD_B64_TEMP%"
echo ZW50VmVyc2lvblxDb25maWdccGx1Z2luc1wwMTAwMDQwMFxzZXR0aW5ncyIgL2Yg >> "%PAYLOAD_B64_TEMP%"
echo Pm51bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09GVFdB >> "%PAYLOAD_B64_TEMP%"
echo UkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXENvbmZpZ1xwbHVn >> "%PAYLOAD_B64_TEMP%"
echo aW5zXDAxMDAwNjAwXHNldHRpbmdzXERpc3RQYWNrYWdlXEFwcFNldHRpbmdzIiAv >> "%PAYLOAD_B64_TEMP%"
echo diAiQWN0T3B0aW9ucyIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo IHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBhZGQgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29uZmlnXHBs >> "%PAYLOAD_B64_TEMP%"
echo dWdpbnNcMDEwMDA2MDBcc2V0dGluZ3NcRGlzdFBhY2thZ2VcQXBwU2V0dGluZ3Mi >> "%PAYLOAD_B64_TEMP%"
echo IC9mID5udWwgMj4mMQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtMTVxPRkZMSU5FX1NP >> "%PAYLOAD_B64_TEMP%"
echo RlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdc >> "%PAYLOAD_B64_TEMP%"
echo cGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEluZm9cTGFzdEh3SW5mbyIg >> "%PAYLOAD_B64_TEMP%"
echo L3YgIkNvbXB1dGVyTmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZl >> "%PAYLOAD_B64_TEMP%"
echo bCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElO >> "%PAYLOAD_B64_TEMP%"
echo RV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cQ29u >> "%PAYLOAD_B64_TEMP%"
echo ZmlnXHBsdWdpbnNcMDEwMDAwMDZcc2V0dGluZ3NcRWtyblxJbmZvXExhc3RId0lu >> "%PAYLOAD_B64_TEMP%"
echo Zm8iIC92ICJWZXJzaW9uIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJvcmxldmVs >> "%PAYLOAD_B64_TEMP%"
echo IDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFkZCAiSEtMTVxPRkZMSU5FX1NP >> "%PAYLOAD_B64_TEMP%"
echo RlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxDb25maWdc >> "%PAYLOAD_B64_TEMP%"
echo cGx1Z2luc1wwMTAwMDAwNlxzZXR0aW5nc1xFa3JuXEluZm9cTGFzdEh3SW5mbyIg >> "%PAYLOAD_B64_TEMP%"
echo L2YgPm51bCAyPiYxDQoNClJlZy5leGUgZGVsZXRlICJIS0xNXE9GRkxJTkVfU09G >> "%PAYLOAD_B64_TEMP%"
echo VFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJlbnRWZXJzaW9uXEluZm8iIC92 >> "%PAYLOAD_B64_TEMP%"
echo ICJFZGl0aW9uTmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAx >> "%PAYLOAD_B64_TEMP%"
echo IHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9T >> "%PAYLOAD_B64_TEMP%"
echo T0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIg >> "%PAYLOAD_B64_TEMP%"
echo L3YgIkZ1bGxQcm9kdWN0TmFtZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3Js >> "%PAYLOAD_B64_TEMP%"
echo ZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZG >> "%PAYLOAD_B64_TEMP%"
echo TElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25c >> "%PAYLOAD_B64_TEMP%"
echo SW5mbyIgL3YgIkluc3RhbGxlZEJ5RVJBIiAvZiA+bnVsIDI+JjENCmlmIG5vdCBl >> "%PAYLOAD_B64_TEMP%"
echo cnJvcmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGRlbGV0ZSAiSEtM >> "%PAYLOAD_B64_TEMP%"
echo TVxPRkZMSU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVy >> "%PAYLOAD_B64_TEMP%"
echo c2lvblxJbmZvIiAvdiAiQWN0aXZlRmVhdHVyZXMiIC9mID5udWwgMj4mMQ0KaWYg >> "%PAYLOAD_B64_TEMP%"
echo bm90IGVycm9ybGV2ZWwgMSBzZXQgL2EgT1BTKz0xDQoNClJlZy5leGUgZGVsZXRl >> "%PAYLOAD_B64_TEMP%"
echo ICJIS0xNXE9GRkxJTkVfU09GVFdBUkVcRVNFVFxFU0VUIFNlY3VyaXR5XEN1cnJl >> "%PAYLOAD_B64_TEMP%"
echo bnRWZXJzaW9uXEluZm8iIC92ICJVbmlxdWVJZCIgL2YgPm51bCAyPiYxDQppZiBu >> "%PAYLOAD_B64_TEMP%"
echo b3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUg >> "%PAYLOAD_B64_TEMP%"
echo IkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVu >> "%PAYLOAD_B64_TEMP%"
echo dFZlcnNpb25cSW5mbyIgL3YgIldlYkFjdGl2YXRpb25TdGF0ZSIgL2YgPm51bCAy >> "%PAYLOAD_B64_TEMP%"
echo PiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4 >> "%PAYLOAD_B64_TEMP%"
echo ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJp >> "%PAYLOAD_B64_TEMP%"
echo dHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYlNlYXRJZCIgL2YgPm51bCAy >> "%PAYLOAD_B64_TEMP%"
echo PiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMrPTENCg0KUmVnLmV4 >> "%PAYLOAD_B64_TEMP%"
echo ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VUXEVTRVQgU2VjdXJp >> "%PAYLOAD_B64_TEMP%"
echo dHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYkNsaWVudENvbXB1dGVyTmFt >> "%PAYLOAD_B64_TEMP%"
echo ZSIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNldCAvYSBPUFMr >> "%PAYLOAD_B64_TEMP%"
echo PTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZUV0FSRVxFU0VU >> "%PAYLOAD_B64_TEMP%"
echo XEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3YgIldlYkxpY2Vu >> "%PAYLOAD_B64_TEMP%"
echo c2VQdWJsaWNJZCIgL2YgPm51bCAyPiYxDQppZiBub3QgZXJyb3JsZXZlbCAxIHNl >> "%PAYLOAD_B64_TEMP%"
echo dCAvYSBPUFMrPTENCg0KUmVnLmV4ZSBkZWxldGUgIkhLTE1cT0ZGTElORV9TT0ZU >> "%PAYLOAD_B64_TEMP%"
echo V0FSRVxFU0VUXEVTRVQgU2VjdXJpdHlcQ3VycmVudFZlcnNpb25cSW5mbyIgL3Yg >> "%PAYLOAD_B64_TEMP%"
echo Ikxhc3RBY3RpdmF0aW9uUmVzdWx0IiAvZiA+bnVsIDI+JjENCmlmIG5vdCBlcnJv >> "%PAYLOAD_B64_TEMP%"
echo cmxldmVsIDEgc2V0IC9hIE9QUys9MQ0KDQpSZWcuZXhlIGFkZCAiSEtMTVxPRkZM >> "%PAYLOAD_B64_TEMP%"
echo SU5FX1NPRlRXQVJFXEVTRVRcRVNFVCBTZWN1cml0eVxDdXJyZW50VmVyc2lvblxJ >> "%PAYLOAD_B64_TEMP%"
echo bmZvIiAvZiA+bnVsIDI+JjENCg0KZWNoby4NCmVjaG8gUmVnaXN0cnkgbW9kaWZp >> "%PAYLOAD_B64_TEMP%"
echo Y2F0aW9ucyBjb21wbGV0ZS4NCmVjaG8gU3VjY2Vzc2Z1bGx5IGRlbGV0ZWQ6ICVP >> "%PAYLOAD_B64_TEMP%"
echo UFMlIHZhbHVlcw0KZWNoby4NCg0KOjogVW5sb2FkIHRoZSBoaXZlDQplY2hvIFVu >> "%PAYLOAD_B64_TEMP%"
echo bG9hZGluZyBTT0ZUV0FSRSBoaXZlLi4uDQpyZWcgdW5sb2FkIEhLTE1cT0ZGTElO >> "%PAYLOAD_B64_TEMP%"
echo RV9TT0ZUV0FSRSA+bnVsIDI+JjENCmlmIGVycm9ybGV2ZWwgMSAoDQogICAgZWNo >> "%PAYLOAD_B64_TEMP%"
echo byBXQVJOSU5HOiBGYWlsZWQgdG8gdW5sb2FkIGhpdmUgb24gZmlyc3QgYXR0ZW1w >> "%PAYLOAD_B64_TEMP%"
echo dC4NCiAgICBlY2hvIFJldHJ5aW5nIGluIDMgc2Vjb25kcy4uLg0KICAgIHRpbWVv >> "%PAYLOAD_B64_TEMP%"
echo dXQgL3QgMyAvbm9icmVhayA+bnVsDQogICAgcmVnIHVubG9hZCBIS0xNXE9GRkxJ >> "%PAYLOAD_B64_TEMP%"
echo TkVfU09GVFdBUkUgPm51bCAyPiYxDQogICAgaWYgZXJyb3JsZXZlbCAxICgNCiAg >> "%PAYLOAD_B64_TEMP%"
echo ICAgICAgZWNobyBFUlJPUjogRmFpbGVkIHRvIHVubG9hZCBoaXZlIGFmdGVyIHJl >> "%PAYLOAD_B64_TEMP%"
echo dHJ5Lg0KICAgICAgICBlY2hvIFRoZSBoaXZlIHdpbGwgcmVtYWluIGxvYWRlZCB1 >> "%PAYLOAD_B64_TEMP%"
echo bnRpbCBzeXN0ZW0gcmVzdGFydC4NCiAgICApIGVsc2UgKA0KICAgICAgICBlY2hv >> "%PAYLOAD_B64_TEMP%"
echo IEhpdmUgdW5sb2FkZWQgc3VjY2Vzc2Z1bGx5IG9uIHJldHJ5Lg0KICAgICkNCikg >> "%PAYLOAD_B64_TEMP%"
echo ZWxzZSAoDQogICAgZWNobyBIaXZlIHVubG9hZGVkIHN1Y2Nlc3NmdWxseS4NCikN >> "%PAYLOAD_B64_TEMP%"
echo Cg0KOjogUmVzdG9yZSBvcmlnaW5hbCBXaW5SRSBjb25maWd1cmF0aW9uDQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo IFJlc3RvcmluZyBXaW5SRSB0byBub3JtYWwgc3RhdGUuLi4NCmlmIGV4aXN0ICJY >> "%PAYLOAD_B64_TEMP%"
echo OlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmluaS5iYWNrdXAiICgNCiAgICBj >> "%PAYLOAD_B64_TEMP%"
echo b3B5ICJYOlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmluaS5iYWNrdXAiICJY >> "%PAYLOAD_B64_TEMP%"
echo OlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmluaSIgPm51bCAyPiYxDQogICAg >> "%PAYLOAD_B64_TEMP%"
echo ZGVsICJYOlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmluaS5iYWNrdXAiID5u >> "%PAYLOAD_B64_TEMP%"
echo dWwgMj4mMQ0KICAgIGVjaG8gV2luUkUgY29uZmlndXJhdGlvbiByZXN0b3JlZCBm >> "%PAYLOAD_B64_TEMP%"
echo cm9tIGJhY2t1cC4NCikgZWxzZSAoDQogICAgZWNobyBbTGF1bmNoQXBwXSA+ICJY >> "%PAYLOAD_B64_TEMP%"
echo OlxXaW5kb3dzXFN5c3RlbTMyXHdpbnBlc2hsLmluaSINCiAgICBlY2hvIEFwcFBh >> "%PAYLOAD_B64_TEMP%"
echo dGg9WDpcc291cmNlc1xyZWNvdmVyeVxyZWNlbnYuZXhlID4+ICJYOlxXaW5kb3dz >> "%PAYLOAD_B64_TEMP%"
echo XFN5c3RlbTMyXHdpbnBlc2hsLmluaSINCiAgICBlY2hvIERlZmF1bHQgV2luUkUg >> "%PAYLOAD_B64_TEMP%"
echo Y29uZmlndXJhdGlvbiByZXN0b3JlZC4NCikNCg0KOjogQ3JlYXRlIGNsZWFudXAg >> "%PAYLOAD_B64_TEMP%"
echo c2NyaXB0IHRvIGhhbmRsZSBsb2NrZWQgZmlsZXMNCmVjaG8gQ3JlYXRpbmcgY2xl >> "%PAYLOAD_B64_TEMP%"
echo YW51cCBzY3JpcHQuLi4NCj4gIiVURU1QJVxfY2xlYW51cC5jbWQiICgNCiAgICBl >> "%PAYLOAD_B64_TEMP%"
echo Y2hvIEBlY2hvIG9mZg0KICAgIGVjaG8gdGltZW91dCAvdCAyIF4+bnVsDQo6OiAg >> "%PAYLOAD_B64_TEMP%"
echo ICBlY2hvIGF0dHJpYiAtaCAtcyAtciAiJVN5c3RlbVJvb3QlXFN5c3RlbTMyXHdp >> "%PAYLOAD_B64_TEMP%"
echo bnBlc2hsLmluaS5iYWNrdXAiIDJePm51bA0KOjogICAgZWNobyBkZWwgL2YgL3Eg >> "%PAYLOAD_B64_TEMP%"
echo IiVTeXN0ZW1Sb290JVxTeXN0ZW0zMlx3aW5wZXNobC5pbmkuYmFja3VwIiAyXj5u >> "%PAYLOAD_B64_TEMP%"
echo dWwNCiAgICBlY2hvIGRlbCAvZiAvcSAiJVN5c3RlbVJvb3QlXFN5c3RlbTMyXE9m >> "%PAYLOAD_B64_TEMP%"
echo ZmxpbmUtUmVzZXQuY21kIiAyXj5udWwNCiAgICBlY2hvIGRlbCAvZiAvcSAiJSV+ >> "%PAYLOAD_B64_TEMP%"
echo ZjAiIDJePm51bA0KKQ0KDQo6OiBMYXVuY2ggY2xlYW51cCBzY3JpcHQgaW4gYmFj >> "%PAYLOAD_B64_TEMP%"
echo a2dyb3VuZA0Kc3RhcnQgIiIgL21pbiAiJVRFTVAlXF9jbGVhbnVwLmNtZCINCg0K >> "%PAYLOAD_B64_TEMP%"
echo ZWNoby4NCmVjaG8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09DQplY2hvIFNVQ0NFU1M6IEVTRVQtUmVzZXQgY29tcGxldGUuDQplY2hv >> "%PAYLOAD_B64_TEMP%"
echo ID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQ0KZWNo >> "%PAYLOAD_B64_TEMP%"
echo byBUYXJnZXQgc3lzdGVtOiAlV0lORElSJQ0KZWNobyBSZWdpc3RyeSB2YWx1ZXMg >> "%PAYLOAD_B64_TEMP%"
echo ZGVsZXRlZDogJU9QUyUNCmVjaG8gPT09PT09PT09PT09PT09PT09PT09PT09PT09 >> "%PAYLOAD_B64_TEMP%"
echo PT09PT09PT09PT09PT09DQplY2hvLg0KZWNobyBOT1RFOiBFU0VUIHdpbGwgbmVl >> "%PAYLOAD_B64_TEMP%"
echo ZCB0byBiZSByZWFjdGl2YXRlZCB3aGVuIFdpbmRvd3MgYm9vdHMuDQplY2hvLg0K >> "%PAYLOAD_B64_TEMP%"
echo ZWNobyBQcmVzcyBhbnkga2V5IHRvIHJlYm9vdCBvciBDVFJMK0MgdG8gY2FuY2Vs >> "%PAYLOAD_B64_TEMP%"
echo Li4uDQpwYXVzZSA+bnVsDQp3cGV1dGlsIHJlYm9vdA== >> "%PAYLOAD_B64_TEMP%"
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
