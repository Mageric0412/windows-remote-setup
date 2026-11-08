#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Get-ChildItem $root -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
}
. (Join-Path $root 'common.ps1')
Assert-SupportedPlatform -Version '10.0.14393' -InstallationType 'Server' -Architecture 'AMD64'
Assert-SupportedPlatform -Version '10.0.26100' -InstallationType 'Client' -Architecture 'ARM64'
foreach ($case in @(
    @{ Version = '6.3.9600'; InstallationType = 'Server'; Architecture = 'AMD64' },
    @{ Version = '10.0.20348'; InstallationType = 'Server Core'; Architecture = 'AMD64' },
    @{ Version = '10.0.20348'; InstallationType = ''; Architecture = 'AMD64' },
    @{ Version = '10.0.19045'; InstallationType = 'Client'; Architecture = 'x86' }
)) {
    $rejected = $false
    try { Assert-SupportedPlatform @case } catch { $rejected = $true }
    if (-not $rejected) { throw 'An unsupported platform was accepted.' }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'install.ps1') -CheckOnly
if ($LASTEXITCODE -ne 0) { throw 'Actual Windows platform preflight failed.' }

$temp = Join-Path $env:TEMP ('remote-setup-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
$serviceCreated = $false
$testService = 'RemoteSetupValidation'
try {
    $sample = Join-Path $temp 'sample.txt'
    [IO.File]::WriteAllText($sample, 'original')
    $hash = (Get-FileHash $sample -Algorithm SHA256).Hash
    Assert-InstallerHash -Path $sample -ExpectedHash $hash
    [IO.File]::WriteAllText($sample, 'tampered')
    $rejected = $false
    try { Assert-InstallerHash -Path $sample -ExpectedHash $hash } catch { $rejected = $true }
    if (-not $rejected) { throw 'Tampered content was accepted.' }

    # Exercise the real SCM with an inert service, not a remote-access agent.
    if (Get-Service $testService -ErrorAction SilentlyContinue) { throw 'Test service name already exists.' }
    $source = Join-Path $temp 'Service.cs'
    $binary = Join-Path $temp 'Service.exe'
    @'
using System.ServiceProcess;
public class TestService : ServiceBase {
    public TestService() { ServiceName = "RemoteSetupValidation"; }
    public static void Main() { ServiceBase.Run(new TestService()); }
}
'@ | Set-Content $source -Encoding ASCII
    & "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$binary" /reference:System.ServiceProcess.dll $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile inert test service.' }
    New-Service -Name $testService -BinaryPathName ('"{0}"' -f $binary) -StartupType Manual | Out-Null
    $serviceCreated = $true
    Set-DelayedService -Name $testService
    # Repeating setup must also succeed on an already-running service.
    Set-DelayedService -Name $testService
    if ((Get-Service $testService).Status -ne 'Running') { throw 'Service is not running.' }
    Write-Host 'PASS: syntax, supported/rejected platforms, preflight, hash tampering, real delayed-auto service setup and repeat setup.'
} finally {
    if ($serviceCreated) {
        Stop-Service $testService -ErrorAction SilentlyContinue
        & "$env:SystemRoot\System32\sc.exe" delete $testService
    }
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
