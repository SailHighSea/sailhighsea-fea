# Phase 7: Polish and release (weeks 13 to 14)

**Status:** Done on this branch (see CHANGELOG.md, Phase 7). Nothing was published.

## Do
1. Accessibility pass: screen reader labels, large text, contrast checks in all three modes, reduced motion.
2. App lock (biometrics on mobile and macOS/Windows where supported). Export CSV.
3. Empty, loading and error states for every screen. First-run onboarding.
4. App icons and names for all platforms; privacy policy page text.
5. `.github/workflows/build.yml` matrix: windows-latest (x64), windows-11-arm (Arm64), macos-latest (macOS and iOS), ubuntu-latest (Linux and Android). Upload artifacts.
6. Release checklist in `docs/RELEASE.md`: Play Console, App Store Connect, Microsoft Store/MSIX, notarised macOS, Linux packages (deb, AppImage). Do not publish anything without asking.
7. Final `test/` build set and `BUILD_REPORT.md`.
