$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Install Flutter 3.50.1 and add its bin directory to PATH. See README.md.'
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed. Run flutter doctor -v.' }
New-Item -ItemType Directory -Force -Path dist | Out-Null
Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'dist/MT-Windows-x64.zip' -Force
Write-Host 'Ready: dist/MT-Windows-x64.zip'
Write-Host 'Extract the ENTIRE archive and run markov_turing_studio.exe.'
