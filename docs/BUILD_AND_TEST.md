# Building and putting outputs in `test/`

Claude Code does the compiling. After each phase run `scripts/build_test.sh` (macOS/Linux/Git Bash) or `scripts/build_test.ps1` (Windows). They build every target the current OS can build and copy results here:

```
test/
  android/   app-release.apk (and app-debug.apk)
  windows-x64/    folder with the .exe and DLLs (zipped as windows-x64.zip)
  windows-arm64/  same, built with --target-platform windows-arm64 when Flutter and the machine support it
  macos/     FamilyExpenses.app (zipped)
  linux/     bundle folder (tar.gz)
  ios/       Runner.app for simulator (Mac only; no signing needed)
  BUILD_REPORT.md   what was built, what was skipped and why, version, date
```

## Rules for Claude Code
- Run `flutter doctor -v` first and record the result in `BUILD_REPORT.md`.
- Build only what this OS supports; never fake an output. If a target is skipped, say why and what is needed.
- Use `--dart-define-from-file=.env.json` for Supabase keys (gitignored). Never copy `.env.json` into `test/`.
- After building, launch the host-OS build once (smoke test) and report what you saw. For Android, install on an emulator if one is available (`flutter emulators`).
- `test/` is for build output only; add it to `.gitignore` except `test/README.md`. Unit tests live in `tests/`.
- If something cannot compile because of a missing SDK or licence, tell the user the exact command to fix it.

## Targets not buildable here
Build them in CI. Phase 7 asks Claude Code to add `.github/workflows/build.yml` with matrix jobs: windows-latest (x64), windows-11-arm (Arm64), macos-latest (macOS + iOS simulator), ubuntu-latest (Linux + Android). Artifacts download into `test/` by hand or with `gh run download`.
