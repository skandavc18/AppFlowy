#requires -Version 7.0
param(
  [string]$CargoExecutable = 'cargo.exe',
  [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$rustRoot = Join-Path (Split-Path -Parent $AppRoot) 'rust-lib'
$targetRoot = Join-Path $rustRoot 'target'
$expectedLibrary = Join-Path $targetRoot 'x86_64-pc-windows-msvc/release/dart_ffi.dll'
$stagedLibrary = Join-Path $AppRoot 'windows/flutter/dart_ffi/dart_ffi.dll'
$reportDirectory = Join-Path $AppRoot 'build/performance'
$log = Join-Path $reportDirectory 'windows-rust-release-build.log'
$cargo = (Get-Command $CargoExecutable -ErrorAction Stop).Source
[IO.Directory]::CreateDirectory($reportDirectory) | Out-Null

# Flutter does not build this DLL: its CMake install step copies the last staged
# backend into BOTH configurations. Never let an old `appflowy-core-dev` build
# silently turn a Flutter Release bundle into an unoptimized database runtime.
# Cargo checks the current locked sources and can reuse a verified fresh artifact.
Write-Host 'Building optimized Windows Rust backend (shared by Release and Debug).'
Push-Location $rustRoot
try {
  $output = @(& $cargo rustc --locked --release --package dart-ffi --lib `
    --crate-type cdylib --features dart --target x86_64-pc-windows-msvc `
    --target-dir $targetRoot --message-format=json-render-diagnostics 2>&1 |
    Tee-Object -FilePath $log)
  if ($LASTEXITCODE -ne 0) { throw "Rust backend build failed. See $log" }
} finally {
  Pop-Location
}

$artifacts = @(foreach ($line in $output) {
  try { $message = $line.ToString() | ConvertFrom-Json -ErrorAction Stop }
  catch { continue }
  if ($message.reason -eq 'compiler-artifact' -and
      $message.target.name -eq 'dart_ffi' -and
      $message.filenames -contains $expectedLibrary) {
    $message
  }
})
if ($artifacts.Count -ne 1 -or $artifacts[0].profile.opt_level -ne '3' -or
    $artifacts[0].profile.debug_assertions -ne $false) {
  throw 'Cargo did not confirm the expected optimized Windows backend. The staged DLL was not changed.'
}
$library = Get-Item -LiteralPath $expectedLibrary
if ($library.Length -eq 0) { throw 'The optimized Rust backend is empty.' }
$hash = (Get-FileHash -LiteralPath $expectedLibrary -Algorithm SHA256).Hash
[IO.Directory]::CreateDirectory((Split-Path -Parent $stagedLibrary)) | Out-Null
Copy-Item -LiteralPath $expectedLibrary -Destination $stagedLibrary -Force
if ((Get-FileHash -LiteralPath $stagedLibrary -Algorithm SHA256).Hash -ne $hash) {
  throw 'Staged Rust backend verification failed.'
}

[pscustomobject]@{
  Profile = 'release'
  OptimizationLevel = $artifacts[0].profile.opt_level
  CargoFresh = $artifacts[0].fresh
  Path = $library.FullName
  StagedPath = $stagedLibrary
  Bytes = $library.Length
  ModifiedUtc = $library.LastWriteTimeUtc.ToString('o')
  Sha256 = $hash
}