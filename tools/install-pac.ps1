<#
Download and silently install PAC 2026 on a Windows machine (here, a GitHub-hosted runner).

    install-pac.ps1 -Version 26.0.0.0

The installer is pinned by URL and SHA-256 (the values winget publishes) so a run can never
pick up a different build by accident. ACCEPT_AXES4_EULA=1 is the licence switch axes4
documents for silent installs. PAC installs per user, under %LOCALAPPDATA%\PAC.
#>
param([string]$Version = '26.0.0.0')
$ErrorActionPreference = 'Stop'
$builds = @{
    '26.0.0.0' = @{
        Url    = 'https://pac.pdf-accessibility.org/_Resources/Persistent/4/b/c/3/4bc303c97b45e0ecbacad67c308d75dbe015b38a/PAC_Setup.26.0.0.0.exe'
        Sha256 = 'DAB632D25D95AF94C8FCBF4870CC0FE7B2A39430E792523E0AFC5068C3B6D45C'
    }
    '26.1.0.0' = @{
        Url    = 'https://pac.pdf-accessibility.org/_Resources/Persistent/2/a/a/4/2aa4ee46c593ff12c2e6ef99bebe13f8105ccce5/PAC_Setup.26.1.0.0.exe'
        Sha256 = '662DAEBD399F5F4D04C936DF2E9574118A062D87334460A20EAC164ED14367FD'
    }
}
if (-not $builds.ContainsKey($Version)) { throw "No pinned installer for PAC $Version" }
$b = $builds[$Version]
$tmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$exe = Join-Path $tmp "PAC_Setup.$Version.exe"
Write-Host "Downloading PAC $Version"
Invoke-WebRequest -Uri $b.Url -OutFile $exe -UseBasicParsing
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($hash -ne $b.Sha256) { throw "Installer hash $hash does not match the pinned $($b.Sha256)" }
Write-Host "Installer hash verified: $hash"
$log = Join-Path $tmp 'pac-install.log'
$p = Start-Process -FilePath $exe -ArgumentList '/quiet', 'ACCEPT_AXES4_EULA=1', '/log', $log -Wait -PassThru
$pac = Join-Path $env:LOCALAPPDATA 'PAC\PAC.exe'
if ($p.ExitCode -ne 0 -or -not (Test-Path $pac)) {
    if (Test-Path $log) { Get-Content $log -Tail 40 }
    throw "PAC install failed (exit $($p.ExitCode))"
}
Write-Host "PAC $Version installed at $pac ($((Get-Item $pac).VersionInfo.FileVersion))"
