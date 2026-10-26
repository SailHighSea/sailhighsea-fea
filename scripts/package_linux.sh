#!/usr/bin/env bash
# Packages the Linux release bundle.
#   scripts/package_linux.sh deb       build/linux/x64/release/bundle
#   scripts/package_linux.sh appimage  build/linux/x64/release/bundle
# Output goes to the current directory. Nothing is uploaded anywhere.
set -euo pipefail
KIND="${1:?deb or appimage}"; BUNDLE="$(cd "${2:?path to the Linux bundle}" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$ROOT/pubspec.yaml")"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
ICON="$ROOT/assets/icon/icon.png"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

desktop_file() { cat <<DESK
[Desktop Entry]
Type=Application
Name=FET Family Expenses Tracker
Comment=Household expense tracker
Exec=$1
Icon=family-expenses
Categories=Office;Finance;
Terminal=false
DESK
}

case "$KIND" in
  deb)
    PKG="$WORK/pkg"
    mkdir -p "$PKG/DEBIAN" "$PKG/opt/family-expenses" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/1024x1024/apps"
    cp -r "$BUNDLE"/. "$PKG/opt/family-expenses/"
    ln -s /opt/family-expenses/family_expenses "$PKG/usr/bin/family-expenses"
    desktop_file family-expenses > "$PKG/usr/share/applications/family-expenses.desktop"
    cp "$ICON" "$PKG/usr/share/icons/hicolor/1024x1024/apps/family-expenses.png"
    cat > "$PKG/DEBIAN/control" <<CTRL
Package: family-expenses
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0, libsecret-1-0, libjsoncpp25 | libjsoncpp1
Maintainer: FET Family Expenses Tracker <noreply@example.invalid>
Description: Household expense tracker
 Local-first family expense tracker with budgets, goals and bills.
CTRL
    dpkg-deb --build --root-owner-group "$PKG" "family-expenses_${VERSION}_${ARCH}.deb";;
  appimage)
    APPDIR="$WORK/Family_Expenses.AppDir"
    mkdir -p "$APPDIR/usr/bin"
    cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"
    desktop_file family_expenses > "$APPDIR/family-expenses.desktop"
    cp "$ICON" "$APPDIR/family-expenses.png"
    printf '#!/bin/sh\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/family_expenses" "$@"\n' > "$APPDIR/AppRun"
    chmod +x "$APPDIR/AppRun"
    TOOL="$WORK/appimagetool"
    curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$TOOL"
    ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "Family_Expenses-${VERSION}-x86_64.AppImage";;
  *) echo "unknown kind $KIND"; exit 1;;
esac
