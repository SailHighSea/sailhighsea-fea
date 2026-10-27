# Testing the app on Google Play

Google Play takes an **app bundle** (`.aab`), not an APK. Every build on GitHub now makes one: open the run on the **Actions** tab, scroll to **Artifacts** and download **android-play-bundle** (unzip it to get `app-release.aab`).

## Before the first upload (once)

1. **Developer account.** https://play.google.com/console, one-time fee of USD 25. A personal account made after November 2023 must run a closed test with at least 12 testers for 14 days in a row before it can publish to production. Testing tracks (internal and closed) work from day one.
2. **Signing key.** Use the same upload key as [ANDROID_SIGNING.md](ANDROID_SIGNING.md). Keep the keystore and its passwords safe. Play App Signing (the default for new apps) re-signs the app for users; your key is then the *upload key*, and Google can reset it if you lose it.
3. **Create the app** in the Play Console: name "FET Family Expenses Tracker", default language, App, Free.
4. **Fill in the required forms** (App content): privacy policy URL (publish `docs/PRIVACY.md`, for example through GitHub Pages or a gist, and paste its link), data safety (the app collects no data on its own servers; Google sign-in and Drive data stay in the person's Google account), target audience (not for children), ads (none), app category (Finance).
5. **Store listing:** short description (80 characters), full description (copy from the README), the 512 px icon (`assets/icon/icon.png` scaled), a 1024 x 500 feature graphic, and at least 2 phone screenshots (`docs/screenshots`).

## Test with a few people (internal testing, ready in minutes)

1. Play Console, **Testing, Internal testing, Create new release**.
2. Upload `app-release.aab`. Each upload needs a higher version code than the last; the build number is the GitHub run number, so this happens by itself.
3. Name the release, **Save, Review release, Start rollout to internal testing**.
4. **Testers** tab: create an email list of up to 100 Google accounts and save it.
5. Copy the **opt-in link** and send it to the testers. They open it on their phone, tap **Become a tester**, then install from Google Play. Updates arrive like any other app.

Use **Closed testing** (any number of people, and the 12 testers for 14 days needed for production) when the app is ready for a wider group.

## Google Sign-in on a Play build

Play re-signs the app, so Google needs the new fingerprint. In the Play Console, **Test and release, App signing**, copy the **SHA-1 of the app signing key** and add it to your Android OAuth client in Google Cloud (Credentials). The desktop client used for sign-in today does not need this; only add it if you switch to an Android client.

## Releasing to everyone later

After the closed test requirement is met: **Production, Create release**, upload the same bundle, and submit for review (usually a few days for a new app).
