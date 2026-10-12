# ESET SafeMode Reset — info

## Folder layout (new rule: ONE file + docs, rest archived)

```text
Eset_Reset_Safemode\
  ESET_Reset.bat   <- THE single file under test. Nothing else is executed.
  info.md          <- this file: why old scripts failed, how the new one works.
  AGENTS.md        <- protocol for reporting success + exact working steps.
  logs\
    cleanup-20261011-2236-SUCCESS.log  <- archived copy of C:\ESET_Reset\cleanup.log
  old\
    Eset_Reset_Safemode.bat          <- original raw reg/file deletes (no phases, no log)
    Eset_Reset_Safemode_desktop.bat  <- arming script w/ hardcoded C:\MySec\... path
    Safemode Version.txt             <- latest ChatGPT draft (never actually ran cleanup)
```

Do not add a second `.bat` — it breaks the iterative test (we need to know
exactly which file produced which log).

> MAINTENANCE WARNING: `ESET_Reset.bat` MUST keep Windows CRLF line endings.
> The 2026-10-11 22:48 run proved LF-only breaks cmd.exe label lookup
> (`call :NeedAdmin` → "cannot find batch label"). After any edit, verify
> with PowerShell: CR count must equal LF count, then re-sync the staged copy
> (`copy` to `C:\ESET_Reset\ESET_Reset.bat`).

## Why the old scripts "crashed and burned"

1. **`Safemode Version.txt`: cleanup section is dead code.** The script sets
   `safeboot`, writes two RunOnce values, then hits `exit` — there is no
   `if /i "%~1"=="/CLEANUP" goto CLEANUP` dispatcher, so the `:CLEANUP` label
   is never reached. Worse, when RunOnce re-invokes `%~f0 /CLEANUP`, the
   script runs the ARM block *again* (re-arms safeboot + reboot loop) instead
   of cleaning. Result: reboots to SafeMode, clears flags via `*UndoSafeMode`,
   but never deletes a single file/reg value.
2. **Quoting + path fragility.** RunOnce values like
   `cmd /c ""C:\Users\...\Desktop\..." /CLEANUP"` nest quotes incorrectly and
   break on spaces. `Eset_Reset_Safemode_desktop.bat` additionally hardcodes
   `C:\MySec\Scripts\Eset-Reset\Eset_Reset_Safemode.bat` — if that path does
   not exist on the test machine, the `&& bcdedit /deletevalue` chain never
   runs either (or the cleanup .bat is simply "file not found", window flashes
   and closes — looks like a crash).
3. **No logging, `cmd /c` closes instantly.** `reg delete` failures
   (`Access Denied`, `unable to find`, self-defense locks) went to `nul` or a
   window that closed in <1s. No way to tell MISSING (fine) apart from FAIL
   (needs ownership/service-stop). Every version looked like "crash and burn".
4. **No service stop / ownership handling.** ESET ACLs + running `ekrn`
   services lock both `license.lf` and several `HKLM\SOFTWARE\ESET\...` values.
   Raw `reg delete` / `del` without `sc stop`, `takeown`, `icacls`,
   `attrib -R -S -H` fails even as admin, especially outside Safe Mode.
5. **Two racing RunOnce entries + `&&` chain.** `*UndoSafeMode` and
   `*CleanESET` order is alphabetical, and `script.bat && bcdedit ...` means a
   missing/failing script blocks the safeboot clear (stuck in SafeMode) or a
   premature reboot skips cleanup. Cleanup must clear safeboot itself in a
   `finally` block, plus keep a fallback entry.
6. **`if not errorlevel 1` + `reg add` clobbering.** The counter pattern miscounts
   (missing values counted as success/fail at random) and the unconditional
   `reg add <key> /f` after each delete resets `%ERRORLEVEL%` and can recreate
   keys with wrong ACLs. No per-value before/after state.
7. **UAC in RunOnce.** `bcdedit` / HKLM writes need admin. The old elevate
   snippet (`Start-Process '%~f0'` with no args) drops `/CLEANUP`, and
   attempting elevation inside RunOnce hangs the boot on a UAC prompt.

## How `ESET_Reset.bat` fixes each one

- **Dispatcher first:** `if /i "%~1"=="/CLEANUP" goto CLEANUP` etc. before any
  arming. `/CLEANUP` can never re-arm.
- **Stage to spaceless path:** ARM copies itself to
  `C:\ESET_Reset\ESET_Reset.bat` and registers
  `cmd /c C:\ESET_Reset\ESET_Reset.bat /CLEANUP` — no inner quotes needed.
  ARM aborts (no reboot) if staging or `bcdedit /set` fails.
- **Everything logged:** `C:\ESET_Reset\cleanup.log`. `:DelVal` does
  `reg query` first → `MISSING` vs `DEL` vs `FAIL` are distinct; `:DelFile`
  does attrib/takeown/icacls/del/verify. Window output mirrors the log.
- **Best-effort service stop:** `sc stop` / `net stop` for
  `ekrn, ekrnEpFw, ESET Service, ESETService, EraAgentSvc` + `taskkill egui/ekrn`
  — all non-fatal, all logged.
- **Safeboot always cleared:** `/CLEANUP` ends with
  `bcdedit /deletevalue` in a finally-style block even when FAIL > 0, plus the
  separate `*ESETResetUndo` fallback. `/TEST` skips bcdedit/shutdown entirely.
- **No UAC in RunOnce:** `/CLEANUP` never elevates; it logs admin state and
  continues for diagnostics. Only interactive modes (ARM/STATUS/UNARM/TEST)
  elevate, preserving args via `-ArgumentList '%MODE%'`.
- **Safe-Mode-proof admin check (`:IsAdmin`):** `net session` needs the Server
  service (absent in SafeMode minimal) and false-reported "NOT admin" on the
  2026-10-11 run even though all 22 deletes succeeded. Now checked via
  `whoami /groups` High-Integrity SID (`S-1-16-12288`), `net session` fallback.

## Verified result 2026-10-11 (ESET NOD32 Antivirus 19.2.10.0)

`RESULT: reg OK=22 FAIL=0 MISSING=7 file OK=1 FAIL=0`, auto-return to normal,
no stale RunOnce. BUT ESET re-activated online ~3 min later: `license.lf`
recreated 22:39 and `UniqueId/WebSeatId/WebClientComputerName/
WebLicensePublicId/WebActivationState/ActiveFeatures/LastActivationResult
("success ... 22:38:26")` reappeared under `CurrentVersion\Info`. Stayed
deleted: `EditionName, FullProductName, InstalledByERA`. Never existed here
(7 MISS): `DNSTimerSec, Token, LastHwf, LegacyUsername, LegacyPassword,
LastHwInfo\{ComputerName,Version}`. Reactivation after reboot is expected
product behavior, not a script issue. See `AGENTS.md` Attempt 2 + recipe.

## Exact test procedure (iterate in this order)

1. **Baseline (normal Windows, admin cmd):**
   `ESET_Reset.bat /STATUS` — record: safeboot present? RunOnce present?
   `license.lf` EXISTS/MISSING? `...\CurrentVersion\Info` values present?
   Save output + `C:\ESET_Reset\cleanup.log` (if any).
2. **Dry run (normal Windows, admin cmd):**
   `ESET_Reset.bat /TEST` — expect `RESULT: reg OK=.. FAIL=.. MISSING=..
   file OK/FAIL`. FAIL here is *expected* outside SafeMode (locks) — the point
   is to confirm logging works and counts are sane. Paste the RESULT line + any
   FAIL value names into `AGENTS.md` "Attempts" table.
3. **Real pass:** `ESET_Reset.bat` (no args) → answer Y → machine reboots to
   SafeMode → cleanup auto-runs → reboots to normal after 30s
   (`shutdown /a` aborts). After logon, open `C:\ESET_Reset\cleanup.log` and
   record the two RESULT lines (TEST vs CLEANUP).
4. **Verify:** `ESET_Reset.bat /STATUS` again — `license.lf` MISSING, Info values
   gone/missing, no safeboot flag, no stale RunOnce entries.
5. **Cancel anytime:** `ESET_Reset.bat /UNARM` + `shutdown /a`.

## What counts as "works" (all must hold)

- [ ] `/TEST` completes without closing instantly, writes RESULT + log.
- [ ] ARM reboots into SafeMode; RunOnce fires without "file not found".
- [ ] `/CLEANUP` log shows `[DEL]` for previously-existing values +
      `license.lf` gone (`dir` confirms).
- [ ] Machine returns to normal mode with no manual `bcdedit` fix.
- [ ] Post-run `/STATUS` confirms deletions persist after reboot.

Report per `AGENTS.md` — one row per attempt, with date, mode, RESULT counts,
log excerpt, and the exact command lines used.
