param(
  [string]$FlutterExecutable = 'flutter.bat'
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $appRoot)

function Get-AppBuildInputSnapshot {
  $inputRoots = @(
    'frontend/appflowy_flutter/lib'
    'frontend/appflowy_flutter/packages'
    'frontend/appflowy_flutter/assets'
    'frontend/appflowy_flutter/windows'
    'frontend/appflowy_flutter/pubspec.yaml'
    'frontend/appflowy_flutter/pubspec.lock'
  )
  $paths = @(git -C $repoRoot ls-files --cached --others --exclude-standard -- @inputRoots)
  if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect build inputs.' }

  # Include ignored/generated Dart parts and resolved package configuration:
  # these are compiled too, even though git diff does not list them.
  $dartRoots = @((Join-Path $appRoot 'lib'))
  $dartRoots += @(Get-ChildItem -LiteralPath (Join-Path $appRoot 'packages') -Directory |
    ForEach-Object { Join-Path $_.FullName 'lib' } | Where-Object { Test-Path $_ })
  $paths += @(Get-ChildItem -LiteralPath $dartRoots -Recurse -File -Filter '*.dart' |
    ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName) })
  $paths += 'frontend/appflowy_flutter/.dart_tool/package_config.json'
  $paths += 'frontend/appflowy_flutter/pubspec.lock'
  $paths | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique |
    ForEach-Object {
      $file = Join-Path $repoRoot $_
      if (Test-Path -LiteralPath $file -PathType Leaf) {
        "$_|$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)"
      }
    }
}

Push-Location $appRoot
try {
  $flutter = (Get-Command $FlutterExecutable -ErrorAction Stop).Source
  $changed = @(git -C $repoRoot diff HEAD --name-only -- '*.dart')
  if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect changed Dart sources.' }
  $changed += @(git -C $repoRoot ls-files --others --exclude-standard -- '*.dart')
  if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect new Dart sources.' }
  $sources = @(
    $changed |
      Where-Object {
        $_ -like 'frontend/appflowy_flutter/lib/*' -or
        $_ -like 'frontend/appflowy_flutter/packages/*/lib/*'
      } |
      Sort-Object -Unique |
      ForEach-Object {
        $path = Join-Path $repoRoot $_
        if (Test-Path $path) { Get-Item $path }
      }
  )
  if ($sources.Count -eq 0) { $sources = @(Get-Item 'lib/main.dart') }
  $latest = $sources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  Write-Host "Latest changed application source: $($latest.FullName)"
  Write-Host "Source timestamp: $($latest.LastWriteTimeUtc.ToString('o'))"
  $inputSnapshot = @(Get-AppBuildInputSnapshot)
  Write-Host "Verifying identical inputs across builds ($($inputSnapshot.Count) files)."

  $reportDirectory = Join-Path $appRoot 'build/performance'
  New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null
  $artifacts = @()

  # Release can remove Debug's kernel. Always restore Debug last.
  foreach ($config in @('Release', 'Debug')) {
    if (@(Get-Process AppFlowy -ErrorAction SilentlyContinue).Count -gt 0) {
      throw 'Close AppFlowy before replacing its runtime bundle.'
    }
    if (@(Get-Process MSBuild -ErrorAction SilentlyContinue).Count -gt 0) {
      throw 'Another MSBuild process is active; do not overlap builds.'
    }

    $started = [DateTime]::UtcNow
    $dartCache = '.dart_tool/flutter_build'
    if (Test-Path $dartCache) {
      # An unchanged main.dart target can reuse an older AOT/kernel payload.
      # Regenerate build outputs without cleaning native dependencies or Pub.
      $backup = ".dart_tool/flutter_build_$($config.ToLower())_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
      Move-Item -Path $dartCache -Destination $backup
      Write-Host "Preserved generated Flutter cache at $backup"
    }

    $generated = 'build/windows/x64/include'
    if (Test-Path $generated) {
      # cppwinrt can fail to overwrite mode-switched generated headers. Keep
      # a backup of this generated directory only; never alter SDK/packages.
      $backup = "build/windows/x64/include_$($config.ToLower())_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
      Move-Item -Path $generated -Destination $backup
      Write-Host "Preserved generated WinRT headers at $backup"
    }

    # Dart-only changes can refresh app.so/kernel while MSBuild reuses the
    # native launcher. A missing output forces a real relink, not a timestamp
    # touch, so both verified executables belong to this build invocation.
    $launcher = "build/windows/x64/runner/$config/AppFlowy.exe"
    if (Test-Path $launcher) {
      $backup = "build/windows/x64/AppFlowy_$($config.ToLower())_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').exe"
      Move-Item -Path $launcher -Destination $backup
      Write-Host "Preserved previous native launcher at $backup"
    }

    Write-Host "Building normal $config at $($started.ToString('o'))"
    $log = Join-Path $reportDirectory "windows-$($config.ToLower())-build.log"
    & $flutter build windows "--$($config.ToLower())" --no-pub --target=lib/main.dart 2>&1 |
      Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "$config build failed. See $log" }

    $changedInputs = @(Compare-Object $inputSnapshot @(Get-AppBuildInputSnapshot))
    if ($changedInputs.Count -gt 0) {
      throw 'Application inputs changed during the builds. Rebuild both configurations from the same sources.'
    }

    $paths = @("build/windows/x64/runner/$config/AppFlowy.exe")
    if ($config -eq 'Release') {
      $paths += 'build/windows/x64/runner/Release/data/app.so'
    } else {
      $paths += 'build/windows/x64/runner/Debug/data/flutter_assets/kernel_blob.bin'
    }
    foreach ($path in $paths) {
      $file = Get-Item $path
      if ($file.Length -eq 0 -or
          $file.LastWriteTimeUtc -le $latest.LastWriteTimeUtc -or
          $file.LastWriteTimeUtc -lt $started) {
        throw "Stale or empty $config artifact: $path (modified $($file.LastWriteTimeUtc.ToString('o')), build started $($started.ToString('o')))"
      }
      $artifacts += [pscustomobject]@{
        Config = $config
        Path = $file.FullName
        Bytes = $file.Length
        BuildStartedUtc = $started.ToString('o')
        ModifiedUtc = $file.LastWriteTimeUtc.ToString('o')
      }
    }
  }

  foreach ($artifact in $artifacts) {
    $file = Get-Item $artifact.Path
    if ($file.Length -ne $artifact.Bytes -or
        $file.LastWriteTimeUtc.ToString('o') -ne $artifact.ModifiedUtc) {
      throw "Artifact changed or disappeared after mode switching: $($artifact.Path)"
    }
  }
  $parity = & (Join-Path $PSScriptRoot 'verify_windows_bundle_parity.ps1') `
    -RunnerRoot (Join-Path $appRoot 'build/windows/x64/runner')
  $artifacts | Format-List
  [pscustomobject]@{
    VerifiedUtc = [DateTime]::UtcNow.ToString('o')
    LatestSourcePath = $latest.FullName
    LatestSourceUtc = $latest.LastWriteTimeUtc.ToString('o')
    BuildInputCount = $inputSnapshot.Count
    BuildInputsSha256 = [Convert]::ToHexString(
      [Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($inputSnapshot -join "`n"))
      )
    )
    BundleParity = $parity
    Artifacts = $artifacts
  } | ConvertTo-Json -Depth 4 |
    Set-Content -Path (Join-Path $reportDirectory 'windows-bundles.json') -Encoding utf8
  Write-Host 'Both normal Windows bundles are fresh, with identical inputs, functional assets and native component sets.'
} finally {
  Pop-Location
}