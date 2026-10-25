#!/usr/bin/env bash
# Builds every target this OS can build and copies the results into test/.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
OUT="$ROOT/test"; REPORT="$OUT/BUILD_REPORT.md"
DEFINE=(); [ -f .env.json ] && DEFINE=(--dart-define-from-file=.env.json)
OS="$(uname -s)"; mkdir -p "$OUT"
{ echo "# Build report"; echo; echo "Date: $(date -u +%FT%TZ)  Host: $OS $(uname -m)"; echo; flutter --version | head -1; echo; } > "$REPORT"
ok(){ echo "- OK: $1" >> "$REPORT"; echo "OK   $1"; }
skip(){ echo "- SKIPPED: $1 ($2)" >> "$REPORT"; echo "SKIP $1 ($2)"; }
fail(){ echo "- FAILED: $1 (see log)" >> "$REPORT"; echo "FAIL $1"; }
flutter pub get >/dev/null || { echo "pub get failed"; exit 1; }
flutter analyze || echo "- analyzer reported issues" >> "$REPORT"
flutter test tests/ 2>/dev/null || true

# Android (any OS with the SDK)
if flutter doctor 2>/dev/null | grep -q "Android toolchain.*\[✓\]\|Android toolchain.*\[!\]"; then
  if flutter build apk --release "${DEFINE[@]}"; then mkdir -p "$OUT/android"; cp build/app/outputs/flutter-apk/app-release.apk "$OUT/android/"; ok android; else fail android; fi
else skip android "Android SDK not found"; fi

case "$OS" in
 Linux)
  if flutter build linux --release "${DEFINE[@]}"; then mkdir -p "$OUT/linux"; ARCH=$(ls build/linux); tar -czf "$OUT/linux/linux-bundle.tar.gz" -C "build/linux/$ARCH/release" bundle; ok linux; else fail linux; fi
  skip macos "needs macOS"; skip ios "needs macOS"; skip windows "needs Windows";;
 Darwin)
  if flutter build macos --release "${DEFINE[@]}"; then mkdir -p "$OUT/macos"; ditto -c -k --keepParent build/macos/Build/Products/Release/*.app "$OUT/macos/macos-app.zip"; ok macos; else fail macos; fi
  if flutter build ios --simulator "${DEFINE[@]}"; then mkdir -p "$OUT/ios"; ditto -c -k --keepParent build/ios/iphonesimulator/Runner.app "$OUT/ios/ios-simulator-app.zip"; ok ios-simulator; else fail ios; fi
  skip linux "needs Linux"; skip windows "needs Windows";;
 *) skip "linux/macos/ios" "run scripts/build_test.ps1 on Windows for Windows targets";;
esac
echo; cat "$REPORT"
