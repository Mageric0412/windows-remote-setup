#requires -Version 5.1
[CmdletBinding()]
param([switch]$CheckOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This installer must run on Windows.'
    }
    $nativeArch = $env:PROCESSOR_ARCHITEW6432
    if (-not $nativeArch) { $nativeArch = $env:PROCESSOR_ARCHITECTURE }
    $windowsInfo = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $osInfo = Get-CimInstance Win32_OperatingSystem
    Write-Host ("System: {0}; {1}; {2}" -f $osInfo.Caption, $windowsInfo.InstallationType, $nativeArch)
    Assert-SupportedPlatform -Version ([version]$osInfo.Version) -InstallationType $windowsInfo.InstallationType -Architecture $nativeArch
    if ($CheckOnly) {
        Write-Host 'Platform preflight passed. No installation or service changes were made.'
        exit 0
    }
    $version = '1.5.1'
    switch ($nativeArch) {
        'AMD64' {
            $asset = "rustdesk-$version-x86_64.msi"
            $expectedHash = '71069183cbc6124273138684ab4032d2211e83efa035886f9c774fe1d3eba3f0'
        }
        'ARM64' {
            $asset = "rustdesk-$version-aarch64.msi"
            $expectedHash = '71900b5212fdc4af20d0d9ba9d6fc1f43767a16cd022bb55e46a17e3b7dc21c1'
        }
        default { throw "Unsupported architecture: $nativeArch. This package supports 64-bit Windows only." }
    }

    Write-Host 'RustDesk remote access setup' -ForegroundColor Cyan
    Write-Host 'Install only on a computer you own or are authorized to manage.'
    Write-Host 'The official installer will request administrator permission.'
    Write-Host 'The RustDesk service will be set to Automatic (Delayed Start).'
    Write-Host 'After installation, set your permanent password in the RustDesk window.'

    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('rustdesk-setup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $installer = Join-Path $workDir $asset
    $logPath = Join-Path $workDir 'install.log'
    $downloadUrl = "https://github.com/rustdesk/rustdesk/releases/download/$version/$asset"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $bundledInstaller = Join-Path (Join-Path $PSScriptRoot 'packages') $asset
    if (Test-Path -LiteralPath $bundledInstaller -PathType Leaf) {
        Write-Host 'Using bundled official MSI.'
        Copy-Item -LiteralPath $bundledInstaller -Destination $installer
    } else {
        Write-Host "Downloading RustDesk $version ($nativeArch) from its official GitHub release..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $installer -TimeoutSec 600
    }
    Assert-InstallerHash -Path $installer -ExpectedHash $expectedHash
    Write-Host 'SHA-256 verified. Complete the installation wizard.' -ForegroundColor Green
    Write-Host "Installation log: $logPath"
    $arguments = '/i "{0}" /norestart INSTALLPRINTER="N" /L*v "{1}"' -f $installer, $logPath
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -eq 1602) { throw 'Installation was cancelled.' }
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "Installer failed (code $($process.ExitCode)). See $logPath. If a newer RustDesk is installed, use that version instead."
    }
    if ($process.ExitCode -in @(3010, 1641)) {
        Write-Warning 'Windows reports that a restart is required. Save your work and restart before testing remote access.'
    }

    Write-Host 'Configuring the service. Approve the administrator prompt.'
    $helperPath = Join-Path $PSScriptRoot 'configure-service.ps1'
    $helperArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $helperPath
    $helper = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $helperArgs -Verb RunAs -Wait -PassThru
    if ($helper.ExitCode -ne 0) {
        throw 'RustDesk was installed, but delayed-start service configuration failed. See the service setup window; do not assume remote access is ready.'
    }
    $serviceConfig = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\RustDesk'
    if ($serviceConfig.Start -ne 2 -or $serviceConfig.DelayedAutoStart -ne 1) {
        throw 'Could not verify Automatic (Delayed Start) for RustDesk.'
    }

    $candidates = @()
    foreach ($root in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) { $candidates += (Join-Path $root 'RustDesk\rustdesk.exe') }
    }
    $client = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($client) {
        Start-Process -FilePath $client | Out-Null
    } else {
        Write-Warning 'Open RustDesk from the Start menu (a custom install location may have been selected).'
    }

    $service = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        throw 'RustDesk service is not running. Check services.msc and the Windows event log.'
    } else {
        Write-Host 'RustDesk service is running.' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'NEXT STEPS (also see README.md):' -ForegroundColor Cyan
    Write-Host '1. RustDesk > Settings > Security > Unlock security settings.'
    Write-Host '2. Set a strong, unique permanent password. Allow password-based approval.'
    Write-Host '3. On your other computer/phone, install RustDesk and enter this PC ID and password.'
    Write-Host '4. Test now, then reboot and wait for delayed service startup; test before anyone logs in.'
    Write-Host 'Windows schedules the startup delay; it is not a fixed number of seconds.'
    Write-Host 'Keep the PC powered on, connected to the Internet, and awake.'
    Write-Host 'Installation completed; remote connectivity has not yet been tested.'
    exit 0
} catch {
    Write-Host ''
    Write-Host ('SETUP FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Check your Internet connection and administrator permission, then retry.'
    Write-Host 'Official downloads: https://github.com/rustdesk/rustdesk/releases'
    exit 1
}
