# Builds Windows (x64, and Arm64 when supported) and Android into test\ . Run from any folder.
$ErrorActionPreference = "Continue"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root
$Out = Join-Path $Root "test"; New-Item -ItemType Directory -Force $Out | Out-Null
$Report = Join-Path $Out "BUILD_REPORT.md"
$Define = @(); if (Test-Path ".env.json") { $Define = @("--dart-define-from-file=.env.json") }
"# Build report`n`nDate: $(Get-Date -Format u)  Host: Windows $env:PROCESSOR_ARCHITECTURE`n" | Set-Content $Report
function Ok($n){ "- OK: $n" | Add-Content $Report; Write-Host "OK   $n" }
function Skip($n,$why){ "- SKIPPED: $n ($why)" | Add-Content $Report; Write-Host "SKIP $n ($why)" }
function Fail($n){ "- FAILED: $n" | Add-Content $Report; Write-Host "FAIL $n" }
flutter pub get; flutter analyze; flutter test tests/

flutter build windows --release @Define
if ($LASTEXITCODE -eq 0) {
  $d = Join-Path $Out "windows-x64"; New-Item -ItemType Directory -Force $d | Out-Null
  Compress-Archive -Path "build\windows\x64\runner\Release\*" -DestinationPath (Join-Path $d "windows-x64.zip") -Force
  Ok "windows-x64"
} else { Fail "windows-x64" }

# Arm64: needs Flutter with Windows Arm64 support. Try it; report honestly.
flutter build windows --release --target-platform windows-arm64 @Define
if ($LASTEXITCODE -eq 0 -and (Test-Path "build\windows\arm64\runner\Release")) {
  $d = Join-Path $Out "windows-arm64"; New-Item -ItemType Directory -Force $d | Out-Null
  Compress-Archive -Path "build\windows\arm64\runner\Release\*" -DestinationPath (Join-Path $d "windows-arm64.zip") -Force
  Ok "windows-arm64"
} else { Skip "windows-arm64" "toolchain did not produce an Arm64 build; use the CI job (windows-11-arm) in Phase 7" }

flutter build apk --release @Define
if ($LASTEXITCODE -eq 0) {
  $d = Join-Path $Out "android"; New-Item -ItemType Directory -Force $d | Out-Null
  Copy-Item "build\app\outputs\flutter-apk\app-release.apk" $d; Ok "android"
} else { Skip "android" "Android SDK missing or build failed" }
Skip "macos/ios" "needs a Mac"; Skip "linux" "needs Linux (or WSL2)"
Get-Content $Report
