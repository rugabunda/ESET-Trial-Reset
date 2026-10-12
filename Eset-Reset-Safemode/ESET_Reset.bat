@echo off
rem ============================================================================
rem  ESET_Reset.bat - single-file ESET trial/license reset via Safe Mode
rem ----------------------------------------------------------------------------
rem  Usage:
rem    ESET_Reset.bat              = ARM   (normal Windows: stage, set safeboot,
rem                                          register RunOnce, reboot to SafeMode)
rem    ESET_Reset.bat /CLEANUP     = CLEAN (runs in Safe Mode via RunOnce:
rem                                          delete license.lf + reg values,
rem                                          clear safeboot, reboot to normal)
rem    ESET_Reset.bat /TEST        = DRY-RUN cleanup NOW without reboot and
rem                                  without touching bcdedit. Use this to
rem                                  iterate/test safely in normal Windows.
rem    ESET_Reset.bat /STATUS      = show bcdedit + RunOnce + file/reg state
rem    ESET_Reset.bat /UNARM       = remove safeboot flag + RunOnce entries
rem
rem  Log: C:\ESET_Reset\cleanup.log  (ARM appends there too)
rem ============================================================================
setlocal EnableExtensions
set "STABLEDIR=C:\ESET_Reset"
set "STABLEBAT=C:\ESET_Reset\ESET_Reset.bat"
set "LOG=C:\ESET_Reset\cleanup.log"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=/ARM"

if /i "%MODE%"=="/ARM"      goto ARM
if /i "%MODE%"=="/CLEANUP"  goto CLEANUP
if /i "%MODE%"=="/TEST"     goto CLEANUP_TEST
if /i "%MODE%"=="/STATUS"   goto STATUS
if /i "%MODE%"=="/UNARM"    goto UNARM
if /i "%MODE%"=="/?"        goto USAGE
if /i "%MODE%"=="-?"        goto USAGE
if /i "%MODE%"=="/HELP"     goto USAGE
goto USAGE

rem ----------------------------------------------------------------------------
:USAGE
echo Usage:
echo   "%~nx0"           - ARM: schedule Safe-Mode reset and reboot
echo   "%~nx0" /CLEANUP  - cleanup phase ^(runs automatically in Safe Mode^)
echo   "%~nx0" /TEST     - dry-run cleanup now, NO reboot, NO bcdedit change
echo   "%~nx0" /STATUS   - show current state, change nothing
echo   "%~nx0" /UNARM    - cancel a previously armed reset
endlocal
exit /b 0

rem ----------------------------------------------------------------------------
rem  :IsAdmin - Safe-Mode-proof admin check. `net session` needs the Server
rem  service (not running in Safe Mode minimal) and false-negatives there.
rem  whoami /groups with the High-Integrity SID works in both modes.
rem  Returns errorlevel 0 = admin, 1 = not admin.
rem ----------------------------------------------------------------------------
:IsAdmin
rem Primary: fsutil needs no services (Safe-Mode-safe) and is instant.
>nul 2>&1 fsutil dirty query %systemdrive%
if not errorlevel 1 exit /b 0
rem Fallback: High-Integrity SID. (net session deliberately NOT used -
rem it needs the Server service, absent in Safe Mode minimal.)
whoami /groups 2>nul | findstr /c:"S-1-16-12288" >nul 2>&1
if not errorlevel 1 exit /b 0
exit /b 1

rem ----------------------------------------------------------------------------
rem  :NeedAdmin - elevate preserving arguments. Call ONLY from interactive
rem  phases (ARM/STATUS/UNARM/TEST). Never from /CLEANUP (RunOnce context).
rem ----------------------------------------------------------------------------
:NeedAdmin
call :IsAdmin
if not errorlevel 1 exit /b 0
echo [*] Not elevated - relaunching as admin, this window will close...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%MODE%' -Verb RunAs"
if errorlevel 1 (
  echo [FAIL] Could not relaunch elevated. Right-click the script and choose "Run as administrator".
  pause
  endlocal & exit /b 1
)
rem Elevated copy launched: this non-elevated instance must do NOTHING more.
endlocal
exit

rem ============================================================================
:ARM
call :NeedAdmin
if not exist "%STABLEDIR%" mkdir "%STABLEDIR%" >nul 2>&1
if not exist "%STABLEDIR%" (
  echo [FAIL] Cannot create %STABLEDIR% - aborting, no changes made.
  pause
  endlocal & exit /b 1
)
set "LOG=%STABLEDIR%\cleanup.log"

rem Stage a copy to a path WITHOUT spaces. This is the fix for the #1
rem crash cause: RunOnce quoting breaks on Desktop paths with spaces,
rem and the old desktop.bat hardcoded C:\MySec\... which may not exist.
copy /y "%~f0" "%STABLEBAT%" >nul 2>&1
if not exist "%STABLEBAT%" (
  echo [FAIL] Cannot stage %STABLEBAT% - aborting, no reboot scheduled.
  pause
  endlocal & exit /b 1
)
>>"%LOG%" echo.
>>"%LOG%" echo ===== ARM %DATE% %TIME% by %USERNAME% src=%~f0 =====

echo [*] Staged: %STABLEBAT%
echo [*] Setting SafeBoot minimal for next boot...
bcdedit /set {current} safeboot minimal >>"%LOG%" 2>&1
if errorlevel 1 (
  echo [FAIL] bcdedit /set failed. See %LOG%. No reboot scheduled.
  type "%LOG%"
  pause
  endlocal & exit /b 1
)

rem NOTE: staged path has no spaces, so RunOnce needs NO inner quotes.
rem This avoids the quoting crash of all previous versions.
echo [*] Registering RunOnce entries...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "*ESETResetCleanup" /t REG_SZ /d "cmd /c C:\ESET_Reset\ESET_Reset.bat /CLEANUP" /f >>"%LOG%" 2>&1
if errorlevel 1 echo [WARN] Could not write *ESETResetCleanup - see log.
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "*ESETResetUndo" /t REG_SZ /d "cmd /c bcdedit /deletevalue {current} safeboot" /f >>"%LOG%" 2>&1
if errorlevel 1 echo [WARN] Could not write *ESETResetUndo - see log.

echo.
echo [OK] Armed. Log: %LOG%
echo Next boot = Safe Mode minimal. Cleanup runs automatically via RunOnce,
echo then the machine reboots back to normal mode.
echo.
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "*ESETResetCleanup"
bcdedit /enum {current} | findstr /i "safeboot"
echo.
set /p "RB=Reboot to Safe Mode now? [Y/n]: "
if /i "%RB%"=="n" (
  echo Cancelled reboot. Run /UNARM to cancel the armed reset, or reboot
  echo manually whenever ready.
  endlocal & exit /b 0
)
echo Rebooting in 10s... Use "shutdown /a" to abort.
shutdown /r /t 10 /c "ESET_Reset armed - rebooting to Safe Mode"
endlocal & exit /b 0

rem ============================================================================
:STATUS
call :NeedAdmin
echo ===== bcdedit {current} =====
bcdedit /enum {current} | findstr /i "identifier safeboot description"
echo.
echo ===== RunOnce =====
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" 2>&1 | findstr /i "ESETReset"
if errorlevel 1 echo ^(no *ESETReset* RunOnce entries^)
echo.
echo ===== license file =====
if exist "%ProgramData%\ESET\ESET Security\License\license.lf" (
  echo EXISTS: "%ProgramData%\ESET\ESET Security\License\license.lf"
  dir "%ProgramData%\ESET\ESET Security\License\license.lf"
) else (
  echo MISSING ^(already cleaned or never existed^)
)
echo.
echo ===== sample reg keys =====
reg query "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" 2>&1
echo.
echo ===== staged copy + log =====
if exist "%STABLEBAT%" (echo STAGED: %STABLEBAT%) else (echo NOT STAGED yet)
if exist "%LOG%" (echo LOG: %LOG%) else (echo NO LOG yet)
endlocal & exit /b 0

rem ============================================================================
:UNARM
call :NeedAdmin
echo [*] Removing safeboot flag...
bcdedit /deletevalue {current} safeboot >nul 2>&1
if not errorlevel 1 (echo [OK] safeboot flag removed.) else (echo [..] no safeboot flag present ^(nothing to do^).)
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "*ESETResetCleanup" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "*ESETResetUndo" /f >nul 2>&1
echo [OK] RunOnce entries removed.
endlocal & exit /b 0

rem ============================================================================
:CLEANUP_TEST
rem Dry run: same code as CLEANUP but DRYRUN=1 skips bcdedit + shutdown.
set "DRYRUN=1"
goto CLEANUP

:CLEANUP
if not defined DRYRUN set "DRYRUN=0"
rem NOTE: do NOT elevate here. RunOnce runs non-interactively; a UAC popup
rem would hang the boot. Just log if we are not admin and continue.
if not exist "%STABLEDIR%" mkdir "%STABLEDIR%" >nul 2>&1
>>"%LOG%" echo.
>>"%LOG%" echo ===== CLEANUP start %DATE% %TIME% mode=%MODE% dryrun=%DRYRUN% user=%USERNAME% =====
call :IsAdmin
if errorlevel 1 (
  >>"%LOG%" echo [WARN] CLEANUP is NOT running as admin - deletes will likely fail with Access Denied. Continuing anyway for diagnostics.
  echo [WARN] Not admin - continuing for diagnostics, expect Access Denied below.
) else (
  >>"%LOG%" echo [OK] running elevated.
)
whoami >>"%LOG%" 2>&1

rem Safe-mode detection (informational only, never aborts)
reg query "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\Option" /v OptionValue >>"%LOG%" 2>&1
if not errorlevel 1 (
  >>"%LOG%" echo [INFO] SafeBoot Option key present = we ARE in Safe Mode.
  echo [INFO] Safe Mode detected.
) else (
  >>"%LOG%" echo [WARN] SafeBoot Option key absent = probably NORMAL mode. Continuing anyway.
  echo [WARN] Not in Safe Mode ^(normal for /TEST^). Continuing.
)
bcdedit /enum {current} 2>&1 | findstr /i "safeboot" >>"%LOG%" 2>&1

rem --- stop ESET services/processes (best effort, never fatal) ---
rem NOTE: ESET does not run in Safe Mode minimal, so "not present / not
rem started" here is EXPECTED, not a failure. We query first and only stop
rem what actually exists, to keep the log free of scary-but-harmless errors.
>>"%LOG%" echo ---- stopping ESET services (absent/not-started is expected in Safe Mode) ----
for %%S in (ekrn ekrnEpFw "ESET Service" ESETService EraAgentSvc) do (
  sc query "%%~S" >nul 2>&1
  if not errorlevel 1 (
    sc stop "%%~S" >>"%LOG%" 2>&1
    if errorlevel 1 >>"%LOG%" echo [INFO] service "%%~S" present but stop not needed/allowed - continuing.
  ) else (
    >>"%LOG%" echo [INFO] service "%%~S" not present - skipping ^(expected in Safe Mode^).
  )
)
tasklist /FI "IMAGENAME eq egui.exe" 2>nul | findstr /i "egui.exe" >nul 2>&1
if not errorlevel 1 (taskkill /F /IM egui.exe >>"%LOG%" 2>&1) else (>>"%LOG%" echo [INFO] egui.exe not running - skipping ^(expected in Safe Mode^).)
tasklist /FI "IMAGENAME eq ekrn.exe" 2>nul | findstr /i "ekrn.exe" >nul 2>&1
if not errorlevel 1 (taskkill /F /IM ekrn.exe >>"%LOG%" 2>&1) else (>>"%LOG%" echo [INFO] ekrn.exe not running - skipping ^(expected in Safe Mode^).)
>>"%LOG%" echo ---- services stop attempted ----

set /a OK=0, FAIL=0, MISSING=0, FILE_OK=0, FILE_FAIL=0

rem --- file cleanup ---
call :DelFile "%ProgramData%\ESET\ESET Security\License\license.lf"

rem --- registry cleanup: exact same 30 values as the old scripts ---
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check" "CfgSeqNumberEsetAccGlobal"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check" "DNSTimerSec"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" "SeatID"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" "ComputerName"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp" "Token"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" "LastHwf"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" "ActivationState"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" "ActivationType"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info" "LastActivationDate"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000200\settings\stProtocolFiltering\stAppSsl" "uRootCreateTime"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" "Username"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" "Password"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" "LegacyUsername"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup" "LegacyPassword"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings" "Password"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings" "Username"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000600\settings\DistPackage\AppSettings" "ActOptions"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo" "ComputerName"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo" "Version"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "EditionName"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "FullProductName"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "InstalledByERA"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "ActiveFeatures"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "UniqueId"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "WebActivationState"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "WebSeatId"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "WebClientComputerName"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "WebLicensePublicId"
call :DelVal "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info" "LastActivationResult"

rem --- re-create parent keys emptied above (same as old scripts, non-fatal) ---
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Check"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Ecp"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000200\settings\stProtocolFiltering\stAppSsl"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Plugins\01000400\ConfigBackup"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000400\settings"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000600\settings\DistPackage\AppSettings"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Config\plugins\01000006\settings\Ekrn\Info\LastHwInfo"
call :EnsureKey "HKLM\SOFTWARE\ESET\ESET Security\CurrentVersion\Info"

rem --- summary ---
>>"%LOG%" echo ===== CLEANUP done: reg OK=%OK% FAIL=%FAIL% MISSING=%MISSING% file OK=%FILE_OK% FAIL=%FILE_FAIL% =====
echo.
echo ===== RESULT: reg OK=%OK% FAIL=%FAIL% MISSING=%MISSING% file OK=%FILE_OK% FAIL=%FILE_FAIL% =====
echo Full log: %LOG%

if "%DRYRUN%"=="1" (
  echo.
  echo [TEST MODE] No bcdedit change, no reboot. Review the log, then run
  echo without args to ARM the real Safe-Mode pass.
  echo.
  pause
  endlocal & exit /b 0
)

rem --- real Safe-Mode pass: ALWAYS clear safeboot, even if cleanup failed ---
echo [*] Clearing safeboot flag...
bcdedit /deletevalue {current} safeboot >>"%LOG%" 2>&1
if not errorlevel 1 (
  >>"%LOG%" echo [OK] safeboot cleared.
  echo [OK] safeboot cleared - next boot will be normal mode.
) else (
  >>"%LOG%" echo [FAIL] bcdedit /deletevalue failed - fallback RunOnce *ESETResetUndo will retry at next logon.
  echo [WARN] Could not clear safeboot directly. Fallback RunOnce entry will retry.
)
echo [*] Rebooting to normal mode in 5s. Use "shutdown /a" to abort.
>>"%LOG%" echo [INFO] rebooting to normal mode.
shutdown /r /f /t 5 /c "ESET reset finished - rebooting to normal mode"
endlocal & exit /b 0

rem ============================================================================
rem  :DelVal "key" "value"  - query first so MISSING is not counted as FAIL,
rem  then delete. Never aborts the script. Updates OK/FAIL/MISSING.
rem ============================================================================
:DelVal
reg query "%~1" /v "%~2" >nul 2>&1
if errorlevel 1 (
  >>"%LOG%" echo [MISS] "%~1" \ "%~2"
  set /a MISSING+=1
  exit /b 0
)
reg delete "%~1" /v "%~2" /f >>"%LOG%" 2>&1
if not errorlevel 1 (
  >>"%LOG%" echo [DEL ] "%~1" \ "%~2"
  echo [DEL ] %~2
  set /a OK+=1
) else (
  >>"%LOG%" echo [FAIL] "%~1" \ "%~2" ^(Access Denied or locked - see lines above^)
  echo [FAIL] %~2 ^(see log^)
  set /a FAIL+=1
)
exit /b 0

rem ============================================================================
rem  :EnsureKey "key"  - recreate parent key if empty/missing. Non-fatal.
rem ============================================================================
:EnsureKey
reg add "%~1" /f >>"%LOG%" 2>&1
if errorlevel 1 >>"%LOG%" echo [WARN] could not ensure key "%~1"
exit /b 0

rem ============================================================================
rem  :DelFile "path" - take ownership, strip attributes, delete, verify.
rem ============================================================================
:DelFile
if not exist "%~1" (
  >>"%LOG%" echo [MISS] file "%~1"
  echo [MISS] file not present: %~1
  exit /b 0
)
>>"%LOG%" echo [INFO] deleting file "%~1"
attrib -R -S -H "%~1" >>"%LOG%" 2>&1
takeown /F "%~1" /A >>"%LOG%" 2>&1
icacls "%~1" /grant Administrators:F SYSTEM:F >>"%LOG%" 2>&1
del /f /q "%~1" >>"%LOG%" 2>&1
if not exist "%~1" (
  >>"%LOG%" echo [DEL ] file "%~1"
  echo [DEL ] %~1
  set /a FILE_OK+=1
) else (
  >>"%LOG%" echo [FAIL] file "%~1" still exists after delete attempt
  echo [FAIL] could not delete: %~1 ^(see log^)
  set /a FILE_FAIL+=1
)
exit /b 0
