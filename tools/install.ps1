# Installs zigtodo for the current user:
#   * copies the exe to %LOCALAPPDATA%\Programs\zigtodo
#   * creates a Start Menu shortcut (searchable by typing "zigtodo")
#
# Run:  powershell -ExecutionPolicy Bypass -File tools\install.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'zig-out\bin\zigtodo.exe'

if (-not (Test-Path $src)) {
    Write-Host 'zig-out/bin/zigtodo.exe not found - building...'
    Push-Location $root
    try { zig build -Doptimize=ReleaseSmall } finally { Pop-Location }
}
if (-not (Test-Path $src)) { throw "Build failed: zig build -Doptimize=ReleaseSmall" }

$dir = Join-Path $env:LOCALAPPDATA 'Programs\zigtodo'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $dir 'zigtodo.exe'
Copy-Item $src $exe -Force

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$lnk = Join-Path $startMenu 'zigtodo.lnk'

$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dir
$sc.IconLocation = "$exe,0"
$sc.Description = 'zigtodo - edge-reveal todo panel'
$sc.Save()

Write-Host ''
Write-Host 'zigtodo installed.'
Write-Host ("  exe      : " + $exe)
Write-Host ("  shortcut : " + $lnk)
Write-Host ''
Write-Host "Open the Start Menu and type 'zigtodo' to launch it."
