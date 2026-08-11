# Copies the `diagrams` locale block and the `optionAction.more` key from the
# canonical translations into the bundled copy.
#
# `assets/translations` is a gitignored copy of `frontend/resources/translations`
# and is NOT a strict subset of it — overwriting it wholesale has silently
# destroyed assets-only keys before, so the new block is spliced in instead.

$ErrorActionPreference = 'Stop'

$flutterRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $flutterRoot 'assets\translations\en-US.json'
$source = Join-Path (Split-Path -Parent $flutterRoot) 'resources\translations\en-US.json'

$src = Get-Content $source -Raw
$start = $src.IndexOf('  "diagrams": {')
$end = $src.IndexOf('  "document": {', $start)
if ($start -lt 0 -or $end -lt 0) {
    throw 'The diagrams block was not found in the canonical translations.'
}
$block = $src.Substring($start, $end - $start)

$json = Get-Content $assets -Raw

if ($json -match '"diagrams"\s*:') {
    # Replace the whole block so keys added later reach the bundled copy too.
    $existingStart = $json.IndexOf('  "diagrams": {')
    $existingEnd = $json.IndexOf('  "document": {', $existingStart)
    if ($existingStart -lt 0 -or $existingEnd -lt 0) {
        throw 'The bundled diagrams block could not be delimited.'
    }
    $json = $json.Remove($existingStart, $existingEnd - $existingStart).Insert($existingStart, $block)
}
else {
    $anchor = "      `"embedLink`": `"Embed file link`"`r`n    }`r`n  },`r`n  `"document`": {"
    if ($json -notmatch [regex]::Escape($anchor)) {
        $anchor = "      `"embedLink`": `"Embed file link`"`n    }`n  },`n  `"document`": {"
    }
    if ($json -notmatch [regex]::Escape($anchor)) {
        throw 'The insertion point was not found in the bundled translations.'
    }
    $replacement = $anchor.Replace('  "document": {', "$block  `"document`": {")
    $json = $json.Replace($anchor, $replacement)
}

$moveAnchor = '"toMove": " to move",'
# Scoped to this block: "more": "More" already exists elsewhere in the file.
if ($json -notmatch [regex]::Escape($moveAnchor) + '\s*\r?\n\s*"more"') {
    $json = $json.Replace($moveAnchor, "$moveAnchor`r`n        `"more`": `"More`",")
}

Set-Content $assets $json -NoNewline -Encoding utf8

$check = Get-Content $assets -Raw | ConvertFrom-Json -AsHashtable
Write-Host ('diagrams groups: ' + (($check.diagrams.Keys | Sort-Object) -join ', ')) -ForegroundColor Green
Write-Host ('optionAction.more: ' + $check.document.plugins.optionAction.more) -ForegroundColor Green
