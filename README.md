# ESET Offline Reset Tool v0.2

This tool configures Windows Recovery Environment to automatically reset ESET on the next system restart. Eset offers a 30 trial after, and maintaining user settings.

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

2. **Disarm Mode**: Cleans and removes every trace of itself and restores normal WinRE behavior

## Important Notes

⚠️ **WARNING**: This tool will reset ESET lisence.

- All operations are logged to `ESET_Reset_Tool.log`
- The system will automatically reboot after the reset process
- A scheduled task is created to automatically clean up after the reset

## How It Works

The tool modifies Windows Recovery Environment startup configuration to run a custom script before Windows loads. This script accesses the offline registry hive to remove ESET-specific entries, effectively resetting the product to an unactivated state.

## Troubleshooting

1. If this script is interrupted during mounting/dismounting phase or the mounted folders are open in any application during mounting and or unmounting phases it may cause potential errors. This app is designed to automate the process of fixing resulting stale mount entries, not user error. 

2. If disarm does not complete after arming, Windows Recovery Environment will be stuck loading the script. 

Solution is to mount, restore, and commit the original contents of winre "%MOUNT_DIR%\Windows\System32\winpeshl.ini". This script creates a backup as %MOUNT_DIR%\Windows\System32\winpeshl.ini.backup.  Windows 11 default winpehl.ini contents:

[LaunchApp]
AppPath=X:\sources\recovery\recenv.exe


3. Errors may occur while arming/mounting winre if bitlocker is partially or fully enabled; Starting with Windows 24H2 Microsoft is enforcing bitlocker by default, to varying degrees, even if only by diskpart flags, which can break WinRE mounting. To fix, research the solution to winreagentc error code as it relates to bitlocker. More info: https://www.perplexity.ai/search/can-winre-be-mounted-while-usi-A0xGs_XQRnmeuXq.jwALWw

## Roadmap

UI free Silent --arm and or --disarm install.
