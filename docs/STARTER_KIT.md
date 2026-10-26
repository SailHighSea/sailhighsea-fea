# Starter kit notes (the original project README)

A shared monthly expense app for families. One Flutter codebase for Android, iOS, iPad and Android tablets, foldables, Windows (x64 and Arm64), macOS and Linux.

## How to use this kit

1. Create your project folder and unzip this kit **into it** (so `CLAUDE.md` sits at the folder root).
2. Open a terminal in that folder and start Claude Code (`claude`).
3. Paste: `Read CLAUDE.md and PLAN.md, then start Phase 1. Follow docs/phases/phase-1-foundations.md. When the phase is done, build every platform this machine can build and put the outputs in test/ as described in docs/BUILD_AND_TEST.md.`
4. Test what landed in `test/`, then ask Claude Code to continue with the next phase (`Start Phase 2`, and so on). One phase per session keeps things reviewable.

## What is inside

| Path | What it is |
|---|---|
| `CLAUDE.md` | Standing rules Claude Code reads every session |
| `PLAN.md` | Product scope, architecture, phases overview, open decisions |
| `docs/SPEC.md` | Design tokens, layouts per device, roles, data model, invite flow |
| `docs/BUILD_AND_TEST.md` | How Claude Code compiles each platform and fills `test/` |
| `docs/phases/` | One prompt file per phase (7 phases) |
| `design/mockups/` | 34 mockup screens as HTML (open in a browser) |
| `design/screenshots/` | The same screens as PNG so Claude Code can look at them |
| `scripts/build_test.sh`, `scripts/build_test.ps1` | Build everything possible on this OS into `test/` |
| `test/` | Build outputs land here (empty to start) |

## Honest limits on compiling

Flutter builds each desktop and iOS target only on its own operating system. Claude Code will build what your machine supports and tell you what it skipped:

- Android (APK, and AAB for the store): any OS with the Android SDK
- Windows x64 and Arm64: on Windows
- macOS and iOS: on a Mac with Xcode (iOS test builds need a simulator or signed device)
- Linux: on Linux
- A phase is not "done" until the targets your machine supports build and launch.

For the others, the kit includes CI workflow instructions (Phase 7) so GitHub Actions can produce them.

## Before you start

Make sure you have Flutter (stable), Git, and a Supabase project (free tier is fine). Phase 1 tells Claude Code exactly what to check and what to ask you for.
