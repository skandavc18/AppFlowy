param(
    [string]$JsonInclude = '',
    [string]$OutputDirectory = ''
)

# Offline runner only. No dependency downloads, installs or app termination.
$ErrorActionPreference = 'Stop'
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
if (-not $JsonInclude) {
    $JsonInclude = Join-Path $appRoot 'build\windows\x64\packages\nlohmann.json\build\native\include'
}
if (-not (Test-Path (Join-Path $JsonInclude 'nlohmann\json.hpp'))) {
    throw 'Pass -JsonInclude for an already installed nlohmann.json include directory.'
}
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw 'Run from x64 Visual Studio Developer PowerShell with existing C++ tools.'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $appRoot 'build\site-gesture-native-tests'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
foreach ($name in @('site_gestures_test', 'site_gesture_unknown_test', 'pending_window_request_test', 'javascript_handler_response_test')) {
    $source = Join-Path $PSScriptRoot "$name.cpp"
    $exe = Join-Path $OutputDirectory "$name.exe"
    $obj = Join-Path $OutputDirectory "$name.obj"
    # Flutter's callback templates intentionally leave default parameters unused.
    & cl.exe /nologo /std:c++17 /EHsc /W4 /WX /wd4100 "/I$JsonInclude" "/I$appRoot\windows\flutter\ephemeral\cpp_client_wrapper\include" "/I$appRoot\windows\flutter\ephemeral" $source "/Fe:$exe" "/Fo:$obj"
    if ($LASTEXITCODE -ne 0) { throw "$name compilation failed." }
    & $exe
    if ($LASTEXITCODE -ne 0) { throw "$name regressions failed." }
    Write-Output "PASS $name"
}