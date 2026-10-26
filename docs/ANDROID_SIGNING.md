# Updating the Android app without uninstalling

## Why an update failed
Android only installs an APK over an installed copy when **two things** match or increase:
1. **The signing key is the same.** The CI used to sign with a *debug key that is created fresh on every build machine*, so every APK had a different signature. Android then refuses with "App not installed as package conflicts with an existing package", and the only way in is to uninstall first. Because your data lives on the phone, uninstalling deletes it.
2. **The build number goes up.** It was always `1`. CI now passes `--build-number=<run number>`, so each build is higher than the last.

## One-time fix: a permanent signing key
Make the key once, keep it safe (if you lose it, no future build can update the installed app), and give it to GitHub as secrets.

1. On any computer with Java (`keytool` comes with it):
   ```
   keytool -genkeypair -v -keystore family-expenses.keystore -alias family-expenses \
     -keyalg RSA -keysize 2048 -validity 36500
   ```
   Choose a password and remember it. Keep `family-expenses.keystore` somewhere safe and **never commit it**.
2. Turn it into text (macOS or Linux; on Windows use `certutil -encode` or the PowerShell line below):
   ```
   base64 -w0 family-expenses.keystore        # Linux
   base64 -i family-expenses.keystore         # macOS
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("family-expenses.keystore"))   # PowerShell
   ```
3. GitHub repo, Settings, Secrets and variables, Actions, add four repository secrets:
   - `ANDROID_KEYSTORE_BASE64`: the long text from step 2
   - `ANDROID_KEYSTORE_PASSWORD`: the password you chose
   - `ANDROID_KEY_ALIAS`: `family-expenses`
   - `ANDROID_KEY_PASSWORD`: the key password (the same one if you pressed Enter at that question)
4. Run the build. The log shows no "debug key" warning.

## The one reinstall that cannot be avoided
The apps you have installed now are signed with old throwaway keys, so the **first** build with the permanent key must be installed after uninstalling the old one. **Back up first:** in the old app open Appearance, Privacy and data, "Back up to a file", and keep the file (share it to Google Drive or email it to yourself). After installing, use "Restore from a backup". From then on every new build installs as a normal update and keeps your data.

## Play Store later
For the Play Store, enrol in Play App Signing and upload with this key as the upload key (docs/RELEASE.md).
