# UDAO local verification — Windows PowerShell edition.
# Usage:  powershell -ExecutionPolicy Bypass -File tools\local_verify.ps1
# (PowerShell 5.1 compatible — no && chains, no bash.)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "== flutter pub get =="
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter analyze (expect: No issues found!) =="
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== dart format (applies Dart 3 tall style; first run may rewrite files — commit them) =="
dart format lib test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter test =="
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Phase-02 data layer in detail (FFI in-memory sqlite; sqlite3.dll is
# bundled with sqflite_common_ffi in debug/test — no setup needed).
Write-Host "== flutter test test/data (phase-02 detail) =="
flutter test test/data
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Structure audit is bash; run it through Git Bash when available.
$gitBash = Get-Command bash -ErrorAction SilentlyContinue
if ($gitBash) {
    Write-Host ""
    Write-Host "== Structure checks =="
    bash tools/bootstrap.sh
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "(skipped tools/bootstrap.sh — install Git for Windows for the full audit)"
}

Write-Host ""
Write-Host "Remaining manual steps (see PHASE_02_COMPLETION_REPORT.md):"
Write-Host "  flutter run --flavor play    # Android device/emulator needed"
Write-Host "  flutter run --flavor power   # same, versionName suffix -power"
Write-Host "  flutter run --flavor play --dart-define=SHOWCASE=true   # theme showcase screen"
Write-Host ""
Write-Host "First golden run writes baselines into test/golden/goldens/ - commit them."
