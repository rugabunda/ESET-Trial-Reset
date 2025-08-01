# ESET Offline Reset Tool v5.0

A Windows utility that resets ESET Security products by modifying registry entries through Windows Recovery Environment (WinRE).

## Overview

This tool configures Windows Recovery Environment to automatically reset ESET on the next system restart.

## Requirements

- Windows 10/11
- Administrator privileges
- ESET Security product installed
- BitLocker recovery key (if BitLocker is enabled)
- Bitlocker may have to to be disabled (may cause error during mount).

## Usage

### Interactive Mode
Run the script without parameters for a menu-driven interface:
```batch
ESET_Reset_Tool.cmd
```

### Command Line Mode
```batch
# Configure automatic reset on next reboot without user interation
ESET_Reset_Tool.cmd --arm

# Remove automatic reset configuration without user interaction (triggered automatically by --arm after reboot)
ESET_Reset_Tool.cmd --disarm
```

## What It Does

1. **Arm Mode**: Injects a reset script into WinRE that will:
   - Delete ESET license file
   - Remove ESET activation and configuration registry entries

2. **Disarm Mode**: Removes the reset configuration and restores normal boot behavior

## Important Notes

⚠️ **WARNING**: This tool will reset ESET, requiring reactivation with a license key.

- All operations are logged to `ESET_Reset_Tool.log`
- The system will automatically reboot after the reset process
- BitLocker users must have their recovery key ready
- A scheduled task is created to automatically clean up after the reset

## How It Works

The tool modifies Windows Recovery Environment startup configuration to run a custom script before Windows loads. This script accesses the offline registry hive to remove ESET-specific entries, effectively resetting the product to an unactivated state.

## Troubleshooting

If this app is interrupted during mounting/dismounting phase or the mounted folders are open in any application during mounting and or unmounting phases it may cause potential errors. This app is designed to automate the process of fixing such stale mount entries, but not user error. Errors may occur while arming/mounting winre if bitlocker is partially or fully enabled; to fix, research the solution to dism/winreagentc error code as it relates to bitlocker. More info: https://www.perplexity.ai/search/can-winre-be-mounted-while-usi-A0xGs_XQRnmeuXq.jwALWw

## Roadmap

UI free Silent --arm and or --disarm install.
