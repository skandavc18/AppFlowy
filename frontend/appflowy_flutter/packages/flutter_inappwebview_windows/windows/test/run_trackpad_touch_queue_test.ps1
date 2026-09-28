param(
    [string]$JsonInclude = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
if (-not $JsonInclude) {
    $JsonInclude = Join-Path $appRoot 'build\windows\x64\packages\nlohmann.json\build\native\include'
}
if (-not (Test-Path (Join-Path $JsonInclude 'nlohmann\json.hpp'))) {
    throw 'Pass -JsonInclude pointing at an existing nlohmann.json include directory; this offline fixture does not download dependencies.'
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $appRoot 'build\popup-webview-native-tests'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'Run from an x64 Visual Studio Developer PowerShell (C++ tools required).' }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'No installed Visual Studio C++ tools found.' }
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
}

$source = Join-Path $PSScriptRoot 'trackpad_touch_queue_test.cpp'
$exe = Join-Path $OutputDirectory 'trackpad_touch_queue_test.exe'
$obj = Join-Path $OutputDirectory 'trackpad_touch_queue_test.obj'
& cl.exe /nologo /std:c++17 /EHsc /W4 /WX "/I$JsonInclude" $source "/Fe:$exe" "/Fo:$obj"
if ($LASTEXITCODE -ne 0) { throw 'Native trackpad policy compilation failed.' }
& $exe
if ($LASTEXITCODE -ne 0) { throw 'Native trackpad policy regression failed.' }