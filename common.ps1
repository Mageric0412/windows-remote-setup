Set-StrictMode -Version Latest

function Assert-SupportedPlatform {
    param([version]$Version, [string]$InstallationType, [string]$Architecture)
    if ($Version.Major -lt 10) {
        throw 'Requires Windows Server 2016 or later, or Windows 10/11, with PowerShell 5.1.'
    }
    if ($InstallationType -notin @('Client', 'Server')) {
        throw "Desktop Experience is required. Detected: $InstallationType. Server Core needs a different remote management setup."
    }
    if ($Architecture -notin @('AMD64', 'ARM64')) {
        throw "Unsupported architecture: $Architecture. Requires 64-bit Windows."
    }
}

function Assert-InstallerHash {
    param([string]$Path, [string]$ExpectedHash)
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'SHA-256 verification failed. The installer will not be executed.'
    }
}

function Set-DelayedService {
    param([Parameter(Mandatory = $true)][string]$Name)
    $service = Get-Service -Name $Name -ErrorAction Stop
    & "$env:SystemRoot\System32\sc.exe" config $Name start= delayed-auto
    if ($LASTEXITCODE -ne 0) { throw "Could not configure delayed startup for $Name." }
    if ($service.Status -ne 'Running') { Start-Service -Name $Name -ErrorAction Stop }
    $service.Refresh()
    $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
    $config = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction Stop
    if ($config.Start -ne 2 -or $config.DelayedAutoStart -ne 1) {
        throw 'Service configuration verification failed.'
    }
    Write-Host "$Name is running and configured for Automatic (Delayed Start)." -ForegroundColor Green
}
