#requires -Version 5.1
#requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    Set-DelayedService -Name 'RustDesk'
    exit 0
} catch {
    Write-Host ('SERVICE SETUP FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
