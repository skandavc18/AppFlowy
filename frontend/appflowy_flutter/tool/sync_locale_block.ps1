# Splices one top-level locale block from the canonical translations into the
# bundled copy.
#
# `assets/translations` is a gitignored copy of `frontend/resources/translations`
# and is NOT a strict subset of it — overwriting it wholesale has silently
# destroyed assets-only keys before, so a single block is spliced in instead.
#
#   pwsh -File tool\sync_locale_block.ps1 -Block interactive -NextBlock diagrams
#
# `-NextBlock` names the top-level key that follows it in the canonical file;
# it is what delimits the block, since JSON has no other end marker at this
# level. The same key is used as the insertion point in the bundled copy.

param(
    [Parameter(Mandatory = $true)][string]$Block,
    [Parameter(Mandatory = $true)][string]$NextBlock
)

$ErrorActionPreference = 'Stop'

$flutterRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $flutterRoot 'assets\translations\en-US.json'
$source = Join-Path (Split-Path -Parent $flutterRoot) 'resources\translations\en-US.json'

$open = "  `"$Block`": {"
$nextOpen = "  `"$NextBlock`": {"

function Find-TopLevelBlock([string]$Text, [string]$Opening, [int]$Start = 0) {
    # IndexOf also matches the last two spaces of an indented nested key.
    # For example document.plugins.board must not end the document block.
    $pattern = [regex]::new('(?m)^' + [regex]::Escape($Opening))
    $match = $pattern.Match($Text, $Start)
    if ($match.Success) { return $match.Index }
    return -1
}

$src = Get-Content $source -Raw
$start = Find-TopLevelBlock $src $open
if ($start -lt 0) { throw "The $Block block was not found in the canonical translations." }
$end = Find-TopLevelBlock $src $nextOpen $start
if ($start -lt 0 -or $end -lt 0) {
    throw "The $Block block was not found in the canonical translations."
}
$blockText = $src.Substring($start, $end - $start)

$json = Get-Content $assets -Raw
$existingStart = Find-TopLevelBlock $json $open
if ($existingStart -ge 0) {
    # Replace it wholesale so keys added later reach the bundled copy too.
    $existingEnd = Find-TopLevelBlock $json $nextOpen $existingStart
    if ($existingEnd -lt 0) {
        throw "The bundled $Block block could not be delimited."
    }
    $json = $json.Remove($existingStart, $existingEnd - $existingStart).Insert($existingStart, $blockText)
}
else {
    $insertAt = Find-TopLevelBlock $json $nextOpen
    if ($insertAt -lt 0) {
        throw "The insertion point ($NextBlock) was not found in the bundled translations."
    }
    $json = $json.Insert($insertAt, $blockText)
}

Set-Content $assets $json -NoNewline -Encoding utf8

$check = Get-Content $assets -Raw | ConvertFrom-Json -AsHashtable
Write-Host ("$Block groups: " + (($check[$Block].Keys | Sort-Object) -join ', ')) -ForegroundColor Green
