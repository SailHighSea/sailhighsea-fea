# Phase 1: Foundations (about 1 week)

**Status:** Done and merged. Built (2026-10-25). Tests: `flutter test tests/`.

Read CLAUDE.md, PLAN.md, docs/SPEC.md and look at design/screenshots first.

## Do
1. Run `flutter doctor -v`. Tell me what is missing for each platform. Do not install system software without asking.
2. `flutter create` in the project root (org `app.familyexpenses`, platforms android, ios, windows, macos, linux). Keep `test/` free for build outputs; configure unit tests in `tests/`.
3. Add dependencies from CLAUDE.md. Set up folders per PLAN.md architecture, `analysis_options.yaml` (flutter_lints, strict), `.gitignore` (include `test/*` except `test/README.md`, `.env.json`).
4. `lib/core/theme`: tokens from SPEC section 2 as ThemeExtension. Modes: System, Light, Dark, Pure black. Colour themes: Forest, Ocean, Sunset, Graphite, each with Light/Dark/Pure variants. Persist the choice locally.
5. `lib/core/layout`: adaptive shell with bottom tabs, rail and sidebar per SPEC section 4, plus hinge-aware layout helper. Placeholder pages for every destination.
6. A "Home" page that renders the SPEC section 3 content using hard-coded sample data, matching Main, Tablet and Desktop mockups in all three modes.
7. Appearance page matching Themes, TabAppearance and DeskAppearance, wired to the real theme switch.
8. Golden tests for Home in three modes at widths 390, 1024, 1280.
9. Build and copy outputs per docs/BUILD_AND_TEST.md.

## Done when
`flutter analyze` and tests pass, switching mode and colour theme changes the app live, Home looks like the screenshots at the three sizes, and `test/BUILD_REPORT.md` lists the builds.
