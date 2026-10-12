# AGENTS.md — ESET SafeMode Reset: success-reporting protocol

> Purpose: every test run records the `RESULT:` line + evidence so we converge
> on the **exact steps that work**. No "it worked" without evidence. See `info.md`
> for root-cause analysis and `ESET_Reset.bat` (the ONLY script under test).

## 1. Ground rules for agents

- **Single file rule:** only `ESET_Reset.bat` is executed. Never create, copy,
  or run a second script. Old versions live in `old\` for reference only.
- **Never skip `/STATUS` + `/TEST`:** no ARM (real reboot) until a `/TEST` log
  exists for the current file version.
- **Log-or-it-didn't-happen:** every attempt must record the items in §3.
  Paste the `RESULT:` line verbatim plus the log path.
- **Don't "fix forward" blindly:** one change per iteration (batch edit +
  note the diff vs. the previous version). If a run fails, file it as FAILED with
  evidence — do not overwrite history.
- **Safe commands only in NORMAL mode:** `/STATUS`, `/TEST`, `/UNARM` change
  nothing irreversible. ARM (`ESET_Reset.bat` with no args) triggers a reboot —
  announce it before running.

## 2. Where evidence lives

| Artifact | Path |
|---|---|
| Script under test | `ESET_Reset.bat` (repo folder) → staged copy `C:\ESET_Reset\ESET_Reset.bat` |
| Master log | `C:\ESET_Reset\cleanup.log` (ARM + CLEANUP append here) |
| File target | `%ProgramData%\ESET\ESET Security\License\license.lf` |
| Reg targets | `HKLM\SOFTWARE\ESET\ESET Security\...` (30 values, see script `:DelVal` list) |
| Boot flag | `bcdedit /enum {current}` → `safeboot` line |
| RunOnce | `HKLM\SOFTWARE\...\CurrentVersion\RunOnce` → `*ESETResetCleanup`, `*ESETResetUndo` |

## 3. Report template (copy per attempt)

```markdown
### Attempt N — YYYY-MM-DD HH:MM (mode: /STATUS | /TEST | ARM+/CLEANUP | /UNARM)
- Script SHA / version note: (e.g. "ESET_Reset.bat, 329 lines, head-fix applied")
- Environment: (normal Windows build / SafeMode minimal? admin? ESET version?)
- Command(s) run (exact):
  - `...`
- RESULT line (verbatim): `===== RESULT: reg OK=x FAIL=y MISSING=z file OK=a FAIL=b =====`
- Outcome: SUCCESS | PARTIAL | FAILED
- Evidence:
  - `C:\ESET_Reset\cleanup.log` excerpt (DEL/FAIL lines):
  - `/STATUS` before → after diff:
- Next change (one only):
```

Status definitions:

- **SUCCESS** = all five checks in `info.md` hold (cleanup ran, license.lf
  gone, reg values gone, auto-return to normal mode, persists after reboot).
- **PARTIAL** = script ran + logged, but some FAIL remains (list value names).
- **FAILED** = reboot loop, stuck in SafeMode, RunOnce "file not found", or
   window closed with no log — attach what *was* observed.

## 4. Exact steps that work (script runs clean; ESET reactivates after)

```text
WORKING RECIPE (verified 2026-10-11, ESET NOD32 Antivirus 19.2.10.0):
1. Admin cmd:  ESET_Reset.bat             → answered Y, rebooted to SafeMode
2. (auto)      /CLEANUP in SafeMode       → RESULT: reg OK=22 FAIL=0 MISSING=7 file OK=1 FAIL=0
3. (auto)      reboot to normal (30s timer, safeboot cleared, no stale RunOnce)
Log: C:\ESET_Reset\cleanup.log, archived copy logs\cleanup-20261011-2236-SUCCESS.log
CAVEAT: ESET re-activated online within ~3 min (license.lf + UniqueId/WebSeatId/
LastActivationResult recreated, "success ... 22:38:26"). For a persistent reset,
next test should run with network disconnected and compare /STATUS before→after.
6. Admin cmd:  ESET_Reset.bat /STATUS     → confirm which values stayed deleted
   (EditionName/FullProductName/InstalledByERA gone) vs re-created.
```

## 5. Quick command reference

```cmd
:: always from an elevated prompt, repo folder:
ESET_Reset.bat /STATUS
ESET_Reset.bat /TEST
ESET_Reset.bat
ESET_Reset.bat /UNARM
shutdown /a
type C:\ESET_Reset\cleanup.log
bcdedit /enum {current} | findstr /i safeboot
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
dir "%ProgramData%\ESET\ESET Security\License\"
```
