Write-Host "Building ESET Reset Tool..." -ForegroundColor Green

# Check files exist
if (-not (Test-Path "payload-script.cmd")) {
    Write-Host "ERROR: payload-script.cmd not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path "main-script.cmd")) {
    Write-Host "ERROR: main-script.cmd not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Encode payload
Write-Host "Encoding payload..."
& certutil -encode "payload-script.cmd" "temp.b64" | Out-Null

# Read main script
$mainContent = Get-Content "main-script.cmd" -Raw

# Read base64 (skip certificate headers)
$base64Lines = Get-Content "temp.b64" | Where-Object { $_ -notmatch "CERTIFICATE" -and $_ -ne "" }

# Create replacement content (ONLY the base64 lines)
$replacement = @()
foreach ($line in $base64Lines) {
    $replacement += "echo $line >> ""%PAYLOAD_B64_TEMP%"""
}

# Replace ONLY the placeholder line
$finalContent = $mainContent -replace 'echo BASE64_CONTENT_GOES_HERE >> "%PAYLOAD_B64_TEMP%"', ($replacement -join "`r`n")

# Write final script
Set-Content "ESET-Reset-Tool.cmd" -Value $finalContent -Encoding ASCII

# Cleanup
Remove-Item "temp.b64" -ErrorAction SilentlyContinue

# Verify
$fileSize = (Get-Item "ESET-Reset-Tool.cmd").Length
Write-Host ""
Write-Host "SUCCESS! Created ESET-Reset-Tool.cmd" -ForegroundColor Green
Write-Host "File size: $fileSize bytes"

if ($fileSize -lt 15000) {
    Write-Host "WARNING: File seems small - check if base64 was embedded properly" -ForegroundColor Yellow
}

Read-Host "Press Enter to continue"