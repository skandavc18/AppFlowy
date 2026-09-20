#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$build = Join-Path $PSScriptRoot 'build_windows_backend.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('appflowy-backend-build-' + [Guid]::NewGuid())
$app = Join-Path $root 'frontend/appflowy_flutter'
$rust = Join-Path $root 'frontend/rust-lib'
$staged = Join-Path $app 'windows/flutter/dart_ffi/dart_ffi.dll'
$mock = Join-Path $root 'mock-cargo.ps1'
$scenario = Join-Path $rust 'scenario.txt'
$checks = 0

function Assert-Rejected([string]$Case, [string]$Expected) {
  [IO.File]::WriteAllText($scenario, $Case)
  [IO.File]::WriteAllText($staged, 'keep previous backend')
  $rejected = $false
  try { $null = & $build -CargoExecutable $mock -AppRoot $app }
  catch {
    if ($_.Exception.Message -notlike "*$Expected*") { throw }
    $rejected = $true
  }
  if (-not $rejected) { throw "Accepted invalid native build: $Case" }
  if ([IO.File]::ReadAllText($staged) -ne 'keep previous backend') {
    throw "Invalid native build replaced the staged DLL: $Case"
  }
  $script:checks++
}

try {
  [IO.Directory]::CreateDirectory($rust) | Out-Null
  [IO.Directory]::CreateDirectory((Split-Path -Parent $staged)) | Out-Null
  # This fake Cargo writes only inside the disposable fixture; no compiler,
  # application process, user data or real staged runtime is touched.
  [IO.File]::WriteAllText($mock, @'
$ErrorActionPreference = 'Stop'
foreach ($required in @('rustc', '--locked', '--release', '--lib', '--crate-type',
    'cdylib', '--features', 'dart', '--package', 'dart-ffi', '--target',
    'x86_64-pc-windows-msvc', '--target-dir', '--message-format=json-render-diagnostics')) {
  if ($args -notcontains $required) { throw "Missing Cargo argument: $required" }
}
$case = [IO.File]::ReadAllText((Join-Path $PWD 'scenario.txt'))
$root = $args[[Array]::IndexOf($args, '--target-dir') + 1]
$dll = Join-Path $root 'x86_64-pc-windows-msvc/release/dart_ffi.dll'
[IO.Directory]::CreateDirectory((Split-Path -Parent $dll)) | Out-Null
[IO.File]::WriteAllText($dll, $(if ($case -eq 'empty') { '' } else { 'optimized backend' }))
$global:LASTEXITCODE = 0
if ($case -eq 'failed') { $global:LASTEXITCODE = 101; return }
if ($case -eq 'missing') { return }
$record = @{
  reason = 'compiler-artifact'
  target = @{ name = 'dart_ffi' }
  filenames = @($(if ($case -eq 'wrong-path') { $dll.Replace('release', 'debug') } else { $dll }))
  profile = @{
    opt_level = $(if ($case -eq 'unoptimized') { '0' } else { '3' })
    debug_assertions = ($case -eq 'debug-assertions')
  }
  fresh = ($case -eq 'cached')
} | ConvertTo-Json -Depth 5 -Compress
'non-JSON diagnostic: safely ignored by artifact parsing'
$record
if ($case -eq 'duplicate') { $record }
'@
  )
  foreach ($case in @('rebuilt', 'cached')) {
    [IO.File]::WriteAllText($scenario, $case)
    $result = & $build -CargoExecutable $mock -AppRoot $app
    if ($result.Profile -ne 'release' -or $result.OptimizationLevel -ne '3' -or
        $result.CargoFresh -ne ($case -eq 'cached') -or
        $result.Sha256 -ne (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -or
        [IO.File]::ReadAllText($staged) -ne 'optimized backend') {
      throw "Native build provenance mismatch: $case"
    }
    $checks++
  }
  Assert-Rejected 'failed' 'Rust backend build failed'
  foreach ($case in @('missing', 'wrong-path', 'unoptimized', 'debug-assertions', 'duplicate')) {
    Assert-Rejected $case 'Cargo did not confirm'
  }
  Assert-Rejected 'empty' 'backend is empty'
  Write-Host "$checks optimized-backend build checks passed."
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}