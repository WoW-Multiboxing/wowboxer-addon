# Copy the WoWBoxer addon folder into the AddOns folder of every installed client (Classic Era, Forever).
# Only replaces Interface\AddOns\WoWBoxer; never touches other addons, WTF or the game. Usage:
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 [-Clients _classic_era_,_forever_] [-WowRoot "C:\Program Files (x86)\World of Warcraft"]
param(
  [string[]]$Clients = @('_classic_era_', '_forever_'),
  [string]$WowRoot = 'C:\Program Files (x86)\World of Warcraft'
)
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'WoWBoxer'
if (-not (Test-Path (Join-Path $src 'WoWBoxer.toc'))) { throw "WoWBoxer.toc not found in $src" }
$version = (git -C (Split-Path -Parent $PSScriptRoot) describe --always --dirty 2>$null)
foreach ($c in $Clients) {
  $addons = Join-Path $WowRoot "$c\Interface\AddOns"
  if (-not (Test-Path $addons)) { Write-Host "skip $c (no $addons)"; continue }
  $dst = Join-Path $addons 'WoWBoxer'
  if (Test-Path $dst) { Remove-Item -Recurse -Force -Confirm:$false $dst }
  Copy-Item -Recurse $src $dst
  # stamp the dev version so the in-game log shows which build is installed
  $toc = Join-Path $dst 'WoWBoxer.toc'
  # write without a BOM: WoW would not read '## Interface' behind one (PowerShell 5.1's -Encoding utf8 adds a BOM)
  $text = [IO.File]::ReadAllText($toc) -replace '@project-version@', "dev-$version"
  [IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding $false))
  $n = (Get-ChildItem -Recurse -File $dst).Count
  Write-Host "installed $c -> $dst ($n files, dev-$version)"
}
