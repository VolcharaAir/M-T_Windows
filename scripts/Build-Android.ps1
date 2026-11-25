$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Android build failed. Check Android SDK and licenses with flutter doctor.' }
New-Item -ItemType Directory -Force -Path dist | Out-Null
Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' 'dist/MT.apk' -Force
Write-Host 'Ready: dist/MT.apk (development signing key).'
