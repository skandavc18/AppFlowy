# Moves the AppFlowy workspace out of %TEMP% to a permanent folder and points
# the app at it. Copies first and verifies before changing the setting, and
# leaves the original in place so nothing is lost if this is wrong.
param(
    [string]$Source = 'C:\Users\skand\AppData\Local\Temp\appflowy_integration_test\4c0aec45-6a8e-497b-a8a4-f8b7224b50a3',
    [string]$Target = 'C:\AppFlowyData',
    [string]$Prefs = 'C:\Users\skand\AppData\Roaming\io.appflowy\AppFlowy\shared_preferences.json',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Get-FolderMb($path) {
    if (-not (Test-Path $path)) { return 0 }
    $sum = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
    return [math]::Round($sum / 1MB, 1)
}

if (Get-Process AppFlowy -ErrorAction SilentlyContinue) {
    Write-Output 'AppFlowy is running; close it first.'
    exit 1
}

# The root itself plus every per-server sibling, e.g. "<root>_localhost".
$parent = Split-Path $Source -Parent
$leaf = Split-Path $Source -Leaf
$folders = Get-ChildItem $parent -Directory | Where-Object { $_.Name -like "$leaf*" }

if (-not $folders) {
    Write-Output "nothing found under $parent matching $leaf*"
    exit 1
}

foreach ($folder in $folders) {
    Write-Output ("source {0}  {1} MB" -f $folder.Name, (Get-FolderMb $folder.FullName))
}

if (-not $Apply) {
    Write-Output 'dry run; pass -Apply to copy'
    exit 0
}

New-Item -ItemType Directory -Path $Target -Force | Out-Null

foreach ($folder in $folders) {
    $suffix = $folder.Name.Substring($leaf.Length)
    $to = Join-Path $Target ('workspace' + $suffix)
    Write-Output "copying $($folder.Name) -> $to"
    robocopy $folder.FullName $to /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    $fromMb = Get-FolderMb $folder.FullName
    $toMb = Get-FolderMb $to
    Write-Output ("  verified {0} MB -> {1} MB" -f $fromMb, $toMb)
    if ($toMb -lt $fromMb) {
        Write-Output '  copy is smaller than the source; stopping without changing settings'
        exit 1
    }
}

Copy-Item $Prefs "$Prefs.backup" -Force
$json = Get-Content $Prefs -Raw | ConvertFrom-Json
$key = 'flutter.io.appflowy.appflowy_flutter.path_location'
$newRoot = Join-Path $Target 'workspace'
$json.$key = $newRoot
$json | ConvertTo-Json -Depth 20 | Set-Content $Prefs -Encoding UTF8

Write-Output "path_location -> $newRoot"
Write-Output "backup at $Prefs.backup"
Write-Output 'original left in %TEMP% untouched'
