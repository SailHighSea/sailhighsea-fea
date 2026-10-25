# Release checklist

Nothing here has been done and nothing is published. Every step that sends something to a store, signs something or spends money needs the owner's go-ahead first.

## Before any release
- [ ] `flutter analyze` and `flutter test tests/` are green on CI (the Windows job runs the golden images).
- [ ] `supabase test db` and `deno test` pass against a real Supabase project (never run so far; see PLAN.md "Still to verify").
- [ ] Supabase migrations applied to the production project in order (`supabase/migrations`), edge functions deployed, secrets set (`supabase/README.md`).
- [ ] Version bumped in `pubspec.yaml` (`1.0.0+1`: the part after `+` must go up for every store upload).
- [ ] `docs/PRIVACY.md` has the publisher name, contact email and date, and is hosted at a public URL.
- [ ] Add the real publisher email to the `.deb` control file (`scripts/package_linux.sh`, currently a placeholder).
- [ ] Try the build on real devices: camera and receipt reading, app lock, bill reminders, a foldable, two phones syncing.

## Names, icons, identifiers
- Display name: **Family Expenses** on every platform. Icons are generated from `assets/icon/icon.png` (`dart run flutter_launcher_icons`). Replace that file with the final artwork and regenerate.
- Bundle id today: `app.familyexpenses` on Android, iOS and macOS. Change it before the first store upload if you want a domain you own; it cannot change afterwards.

## Android (Google Play)
1. Create a Play Console developer account (one-off fee).
2. Create an upload keystore and keep it out of git; add `android/key.properties` and a signing config in `android/app/build.gradle.kts` (the repo builds with debug signing for now).
3. `flutter build appbundle --release --dart-define-from-file=.env.json`
4. Upload the `.aab` to an Internal testing track first. Fill in the Data safety form from `docs/PRIVACY.md`, the content rating and the store listing (screenshots from `design/screenshots` style).
5. Camera permission is requested by `image_picker` only when "Take photo" is used.

## iOS (App Store Connect)
1. Apple Developer Program membership, an App ID, a distribution certificate and a provisioning profile.
2. Set the team and signing in Xcode (`ios/Runner.xcworkspace`), then `flutter build ipa --release --dart-define-from-file=.env.json`.
3. Upload with Transporter or `xcrun altool`; test with TestFlight before submitting.
4. App Privacy "nutrition label" from `docs/PRIVACY.md`. Usage texts for camera and photos are already in `Info.plist`. Minimum iOS is 15.5 (ML Kit).
5. CI currently builds an unsigned `.app` only (`ios-unsigned` artifact) to prove it compiles.

## macOS (notarised)
1. Developer ID Application certificate. Set the team in Xcode for `macos/Runner.xcworkspace`; enable Hardened Runtime.
2. `flutter build macos --release --dart-define-from-file=.env.json`
3. Sign, then notarise and staple: `xcrun notarytool submit Family\ Expenses.zip --apple-id ... --team-id ... --wait` then `xcrun stapler staple "Family Expenses.app"`.
4. Make the dmg from the stapled app. CI today produces an unsigned dmg (right-click, Open).
5. For the Mac App Store instead, the sandbox entitlements are already in `macos/Runner/*.entitlements` (network client, user-selected files read-only).

## Windows (Microsoft Store / MSIX)
1. Microsoft Partner Center account and an app name reservation.
2. Add the `msix` package configuration (publisher id, identity name from Partner Center, logo from `assets/icon`), then `dart run msix:create`. Sideloading needs a code-signing certificate; the Store signs it for you.
3. CI builds x64 (`windows-x64.zip`) and tries Arm64 (`windows-11-arm`, marked optional until it has been seen to pass). Submit one package per architecture or a bundle.
4. Windows Hello for the app lock needs nothing extra; the minimum window size is set in `windows/runner/flutter_window.cpp`.

## Linux
- `scripts/package_linux.sh deb <bundle>` makes a `.deb` (installs to `/opt/family-expenses`, `family-expenses` on the PATH, a menu entry and an icon). It was built and its contents checked here; it was not installed.
- `scripts/package_linux.sh appimage <bundle>` makes an AppImage (downloads `appimagetool`). Not run here.
- The app lock is not offered on Linux (no system prompt to ask). Reminders show while the app is open.
- For Flathub or the Snap Store, a separate manifest is needed; not started.

## After publishing
- [ ] Tag the commit, attach the CHANGELOG entry as the release notes.
- [ ] Keep `.env.json`, keystores and certificates out of git (`.gitignore` already lists `.env.json`).
