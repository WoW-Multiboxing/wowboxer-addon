# Install a local TEST BUILD: copy the WoWBoxer addon folder into the AddOns folder of every installed client
# (Classic Era, Forever). Only replaces Interface\AddOns\WoWBoxer; never touches other addons, WTF or the game.
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 [-Clients _classic_era_,_forever_] [-WowRoot "..."]
#                                                              [-Next 0.13.0] [-TestN 1]
# The installed TOC gets the version "<next>-test.N (<short sha>)", e.g. "0.13.0-test.1 (a64a7eb)"; the addon then
# shows an orange TEST BUILD label in its window title (docs/release.md, "Test first, then live").
#   <next>  the latest version tag with the minor bumped (v0.12.0 -> 0.13.0), or -Next
#   N       counts test builds since that tag: a new commit (or new uncommitted changes) gives N+1, installing the
#           same build again keeps N, a new tag starts at 1 again. Kept in tools\.testbuild (not in git), or -TestN.
param(
  [string[]]$Clients = @('_classic_era_', '_forever_'),
  [string]$WowRoot = 'C:\Program Files (x86)\World of Warcraft',
  [string]$Next = '',
  [int]$TestN = 0
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'WoWBoxer'
if (-not (Test-Path (Join-Path $src 'WoWBoxer.toc'))) { throw "WoWBoxer.toc not found in $src" }

# --- version: <next>-test.N (<sha>)
$tag = (git -C $repo describe --tags --abbrev=0 --match 'v[0-9]*' 2>$null)
if (-not $tag) { $tag = 'v0.0.0' }
if (-not $Next) {
  if ($tag -notmatch '^v(\d+)\.(\d+)\.(\d+)') { throw "cannot read the version from tag $tag (use -Next)" }
  $Next = '{0}.{1}.0' -f $Matches[1], ([int]$Matches[2] + 1)
}
# the last commit that changed the addon itself: docs-only commits do not make a new test build
$sha = (git -C $repo log -1 --format=%h --abbrev=7 -- WoWBoxer).Trim()
$dirty = (git -C $repo status --porcelain -- WoWBoxer)
if ($dirty) {
  # uncommitted addon changes: a hash of the diff tells two different dirty builds apart
  $diff = (git -C $repo diff HEAD -- WoWBoxer | Out-String)
  $md5 = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($diff))
  $build = "$sha-dirty" ; $key = "$sha-" + ([BitConverter]::ToString($md5) -replace '-', '').Substring(0, 8)
} else { $build = $sha; $key = $sha }

$stateFile = Join-Path $PSScriptRoot '.testbuild'
$state = @{ next = ''; n = 0; key = '' }
if (Test-Path $stateFile) {
  foreach ($line in Get-Content $stateFile) { if ($line -match '^(\w+)=(.*)$') { $state[$Matches[1]] = $Matches[2] } }
}
if ($TestN -gt 0) { $n = $TestN }
elseif ($state.next -ne $Next) { $n = 1 }
elseif ($state.key -eq $key) { $n = [int]$state.n }
else { $n = [int]$state.n + 1 }
$version = "$Next-test.$n ($build)"

$installed = 0
foreach ($c in $Clients) {
  $addons = Join-Path $WowRoot "$c\Interface\AddOns"
  if (-not (Test-Path $addons)) { Write-Host "skip $c (no $addons)"; continue }
  $dst = Join-Path $addons 'WoWBoxer'
  if (Test-Path $dst) { Remove-Item -Recurse -Force -Confirm:$false $dst }
  Copy-Item -Recurse $src $dst
  $toc = Join-Path $dst 'WoWBoxer.toc'
  # write without a BOM: WoW would not read '## Interface' behind one (PowerShell 5.1's -Encoding utf8 adds a BOM)
  $text = [IO.File]::ReadAllText($toc) -replace '@project-version@', $version
  [IO.File]::WriteAllText($toc, $text, (New-Object Text.UTF8Encoding $false))
  $files = (Get-ChildItem -Recurse -File $dst).Count
  Write-Host "installed $c -> $dst ($files files, $version)"
  $installed++
}
if ($installed -gt 0) {
  [IO.File]::WriteAllText($stateFile, "next=$Next`nn=$n`nkey=$key`n", (New-Object Text.UTF8Encoding $false))
  Write-Host "TEST BUILD $version"
}
