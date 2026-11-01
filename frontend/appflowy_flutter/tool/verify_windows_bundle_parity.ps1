param(
  [Parameter(Mandatory = $true)]
  [string]$RunnerRoot
)

$ErrorActionPreference = 'Stop'
$assets = @{}
$libraries = @{}

foreach ($config in @('Release', 'Debug')) {
  $bundle = Join-Path $RunnerRoot $config
  $root = (Get-Item -LiteralPath (Join-Path $bundle 'data/flutter_assets')).FullName
  $entries = @{}
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    # These are VM bootstrap/code payloads, not functional assets. AOT uses
    # data/app.so instead. All fonts, translations, icons, manifests and other
    # packaged resources must match, including their contents.
    if ($relative -in @('kernel_blob.bin', 'vm_snapshot_data', 'isolate_snapshot_data')) {
      continue
    }
    $entries[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  }
  if ($entries.Count -eq 0) { throw "$config has no functional assets." }
  $assets[$config] = $entries
  $libraries[$config] = @(Get-ChildItem -LiteralPath $bundle -Filter '*.dll' -File |
    Select-Object -ExpandProperty Name | Sort-Object)
  if ($libraries[$config].Count -eq 0) { throw "$config has no native libraries." }
}

$differentNames = @(Compare-Object @($assets.Release.Keys) @($assets.Debug.Keys))
if ($differentNames.Count -gt 0) {
  throw "Functional asset set differs: $($differentNames.InputObject -join ', ')"
}
foreach ($name in $assets.Release.Keys) {
  if ($assets.Release[$name] -ne $assets.Debug[$name]) {
    throw "Functional asset content differs: $name"
  }
}
$differentLibraries = @(Compare-Object $libraries.Release $libraries.Debug)
if ($differentLibraries.Count -gt 0) {
  throw "Native component set differs: $($differentLibraries.InputObject -join ', ')"
}

# This project installs the same separately-built Rust backend into both
# Flutter bundles. Other native DLLs legitimately differ with optimization.
$releaseCore = (Get-FileHash -LiteralPath (Join-Path $RunnerRoot 'Release/dart_ffi.dll') -Algorithm SHA256).Hash
$debugCore = (Get-FileHash -LiteralPath (Join-Path $RunnerRoot 'Debug/dart_ffi.dll') -Algorithm SHA256).Hash
if ($releaseCore -ne $debugCore) { throw 'Rust backend binaries differ between bundles.' }

# Both bundles carry the same complete built-in office editor: the manifest
# written last by the fetch tool, plus every file it lists.
$officeEditors = @{}
foreach ($config in @('Release', 'Debug')) {
  $editor = Join-Path $RunnerRoot "$config/data/office_editor"
  $manifestPath = Join-Path $editor 'APPFLOWY_BUNDLE.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "$config has no built-in office editor."
  }
  $manifestText = Get-Content -LiteralPath $manifestPath -Raw
  $manifest = $manifestText | ConvertFrom-Json
  $files = @(Get-ChildItem -LiteralPath $editor -Recurse -File -Force).Count
  if ($files -ne $manifest.files + 1) {
    throw "$config has an incomplete built-in office editor ($files files, expected $($manifest.files + 1))."
  }
  $officeEditors[$config] = [pscustomobject]@{
    Manifest = $manifestText
    Revision = $manifest.revision
    Files = $files
  }
}
if ($officeEditors.Release.Manifest -ne $officeEditors.Debug.Manifest) {
  throw 'The built-in office editor differs between bundles.'
}

$assetList = ($assets.Release.Keys | Sort-Object | ForEach-Object {
    "$_|$($assets.Release[$_])"
  }) -join "`n"
$digest = [Convert]::ToHexString(
  [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($assetList))
)
[pscustomobject]@{
  FunctionalAssetCount = $assets.Release.Count
  FunctionalAssetsSha256 = $digest
  NativeComponentCount = $libraries.Release.Count
  NativeComponents = $libraries.Release
  RustBackendSha256 = $releaseCore
  OfficeEditorRevision = $officeEditors.Release.Revision
  OfficeEditorFiles = $officeEditors.Release.Files
}