$ErrorActionPreference = 'Stop'
$verify = Join-Path $PSScriptRoot 'verify_windows_bundle_parity.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('appflowy-bundle-parity-' + [Guid]::NewGuid())

function Write-Fixture([string]$RelativePath, [string]$Content) {
  $path = Join-Path $root $RelativePath
  [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  [IO.File]::WriteAllText($path, $Content)
}

function Assert-Rejected([string]$Expected) {
  try {
    $null = & $verify -RunnerRoot $root
  } catch {
    if ($_.Exception.Message -notlike "*$Expected*") { throw }
    return
  }
  throw "Bundle verifier accepted $Expected"
}

try {
  foreach ($config in @('Release', 'Debug')) {
    Write-Fixture "$config/data/flutter_assets/assets/labels.json" '{"label":"same"}'
    Write-Fixture "$config/data/flutter_assets/assets/icon.svg" '<svg/>'
    Write-Fixture "$config/dart_ffi.dll" 'same backend'
    Write-Fixture "$config/viewer.dll" "$config native code"
  }
  Write-Fixture 'Debug/data/flutter_assets/kernel_blob.bin' 'JIT payload'
  Write-Fixture 'Release/data/app.so' 'AOT payload'
  $result = & $verify -RunnerRoot $root
  if ($result.FunctionalAssetCount -ne 2 -or $result.NativeComponentCount -ne 2) {
    throw 'Incorrect asset/component counts.'
  }

  Write-Fixture 'Release/data/flutter_assets/assets/icon.svg' '<different/>'
  Assert-Rejected 'asset content differs'
  Write-Fixture 'Release/data/flutter_assets/assets/icon.svg' '<svg/>'

  Remove-Item -LiteralPath (Join-Path $root 'Release/data/flutter_assets/assets/icon.svg')
  Assert-Rejected 'asset set differs'
  Write-Fixture 'Release/data/flutter_assets/assets/icon.svg' '<svg/>'

  Remove-Item -LiteralPath (Join-Path $root 'Release/viewer.dll')
  Assert-Rejected 'component set differs'
  Write-Fixture 'Release/viewer.dll' 'Release native code'

  Write-Fixture 'Release/dart_ffi.dll' 'outdated backend'
  Assert-Rejected 'backend binaries differ'
  Write-Fixture 'Release/dart_ffi.dll' 'same backend'
  $null = & $verify -RunnerRoot $root
  Write-Host '6 bundle-parity checks passed (matching, asset content, asset names, DLL names, backend, restored).'
} finally {
  if (Test-Path -LiteralPath $root) {
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}