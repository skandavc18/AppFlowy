# Builds the Excalidraw editor AppFlowy embeds.
#
# The editor is the real, unmodified open-source Excalidraw component: this
# script stages the small host app in `tool/excalidraw_host` into the
# excalidraw monorepo (so its workspace resolves React and the package),
# builds it, and copies the static bundle plus the offline fonts into
# `assets/excalidraw/`.
#
#   pwsh tool/build_excalidraw_host.ps1 -ExcalidrawRepo C:\excalidraw
#
# Pass -SkipPackages when the monorepo's own packages are already built.

[CmdletBinding()]
param(
    [string]$ExcalidrawRepo = 'C:\excalidraw',
    [switch]$SkipInstall,
    [switch]$SkipPackages
)

$ErrorActionPreference = 'Stop'

$flutterRoot = Split-Path -Parent $PSScriptRoot
$hostSource = Join-Path $PSScriptRoot 'excalidraw_host'
$assets = Join-Path $flutterRoot 'assets\excalidraw'

if (-not (Test-Path $ExcalidrawRepo)) {
    throw "The excalidraw checkout was not found at $ExcalidrawRepo."
}

# The repo pins yarn 1; resolve it once through npx's cache and drive it with
# node directly, so PowerShell never has to parse `--flag` style arguments.
& npx --yes yarn@1.22.22 --version | Out-Null
$yarnJs = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx') -Recurse -Filter 'yarn.js' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*yarn\bin\yarn.js' } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $yarnJs) {
    throw 'yarn 1.22.22 could not be resolved. Run "npx yarn@1.22.22 --version" once and try again.'
}

function Invoke-Yarn {
    & node $yarnJs @args | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "yarn $($args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Push-Location $ExcalidrawRepo
try {
    if (-not $SkipInstall) {
        Write-Host 'Installing excalidraw dependencies...' -ForegroundColor Cyan
        Invoke-Yarn install --network-timeout 600000
    }
    if (-not $SkipPackages) {
        Write-Host 'Building excalidraw packages...' -ForegroundColor Cyan
        Invoke-Yarn build:packages
    }

    # The host has to live inside the monorepo's `examples/*` workspace or its
    # imports of react and @excalidraw/excalidraw cannot be resolved.
    $staging = Join-Path $ExcalidrawRepo 'examples\appflowy-host'
    if (Test-Path $staging) {
        Remove-Item $staging -Recurse -Force
    }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Copy-Item (Join-Path $hostSource '*') $staging -Recurse -Force

    Write-Host 'Linking the host into the workspace...' -ForegroundColor Cyan
    Invoke-Yarn install --network-timeout 600000

    Write-Host 'Building the host bundle...' -ForegroundColor Cyan
    Invoke-Yarn --cwd ./examples/appflowy-host build

    $built = Join-Path $staging 'dist'
    if (-not (Test-Path $built)) {
        throw 'The host bundle was not produced.'
    }

    # Fonts and the subsetting workers are fetched at runtime relative to the
    # page, so they must sit beside index.html for the editor to work offline.
    # The locale JSON is not: vite already bundled every translation as a lazy
    # chunk, so copying it again would only add weight.
    $prod = Join-Path $ExcalidrawRepo 'packages\excalidraw\dist\prod'
    foreach ($item in @('fonts', 'subset-worker.chunk.js', 'subset-shared.chunk.js')) {
        $from = Join-Path $prod $item
        if (Test-Path $from) {
            Copy-Item $from $built -Recurse -Force
        }
    }
    Get-ChildItem $built -Recurse -Include '*.map' | Remove-Item -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $assets)) {
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
    }

    # Shipped as one archive rather than three hundred loose files: Flutter
    # would otherwise need every directory listed in pubspec, and the app
    # unpacks it once into its data folder on first use.
    $archive = Join-Path $assets 'excalidraw_host.zip'
    if (Test-Path $archive) {
        Remove-Item $archive -Force
    }
    Compress-Archive -Path (Join-Path $built '*') -DestinationPath $archive -CompressionLevel Optimal

    $license = Join-Path $ExcalidrawRepo 'LICENSE'
    if (Test-Path $license) {
        Copy-Item $license (Join-Path $assets 'EXCALIDRAW_LICENSE') -Force
    }

    $size = [math]::Round(((Get-Item $archive).Length / 1MB), 1)
    Write-Host "Excalidraw bundle written to $archive ($size MB)." -ForegroundColor Green
}
finally {
    Pop-Location
}
