# Google Cloud setup for Google Sheets mode

Only needed for a build with `--dart-define=BACKEND=sheets`. One Google Cloud project serves the whole family; nobody else needs to do anything but sign in.

## 1. Create the project and enable two APIs
1. https://console.cloud.google.com, create a project (for example "Family Expenses").
2. APIs and Services, Library: enable **Google Sheets API** and **Google Drive API**.

## 2. Consent screen
1. APIs and Services, OAuth consent screen (Google Auth platform, Branding and Audience).
2. User type **External**. App name "Family Expenses", your email as support and developer contact.
3. Scopes: `.../auth/drive.file` and `.../auth/spreadsheets` (plus the default `openid email profile`).
   - `drive.file` lets the app share the sheet *it created* with another family member.
   - `spreadsheets` lets the app read a sheet another family member shared with it. It is a "sensitive" scope, so Google shows an "unverified app" warning until the app is verified. For a family you can click through it (Advanced, Go to Family Expenses).
4. **Publishing status**
   - *Testing*: only the test users you list can sign in (up to 100), and **Google expires the refresh tokens after 7 days**, so everyone has to reconnect weekly.
   - **In production** (recommended): click "Publish app". Tokens no longer expire after 7 days. Without verification you still get the unverified-app warning and a 100-user cap, which is plenty for a family.
5. While in Testing, add every family member's Google email under Test users.

## 3. OAuth client
1. Credentials, Create credentials, OAuth client ID, application type **Desktop app**. (The app signs in through the browser and listens on `http://127.0.0.1:<port>`; this client type allows that on every platform. Android and iOS client types do not allow a loopback redirect, so do not use them for this build.)
2. Copy the client ID and the client secret. For an installed app the secret is not confidential, but still keep it out of git.

## 4. Build with the client
Put them in `.env.json` (gitignored) next to your other defines, or pass them directly:

```
flutter run --dart-define=BACKEND=sheets \
  --dart-define=GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com \
  --dart-define=GOOGLE_CLIENT_SECRET=GOCSPX-xxxx
```

In CI add them as repository secrets and pass them the same way (see `.github/workflows/build.yml`, which already passes the Supabase ones).

## 5. First use
1. Everyone installs the app and opens **Family**, then **Sign in with Google**.
2. The person who runs the household chooses "I run the household", creates an invite and shows the code or QR.
3. Each family member chooses "I am a family member", pastes or scans the invite, confirms the sharing question, and shows their own code back. The organiser enters it under "Add a member".

## Troubleshooting
- "Google sign-in is not set up in this build": the client ID was not passed with `--dart-define`.
- "Access blocked" or "This app is not verified": add the person as a test user, or publish the app (step 2.4).
- Everyone is asked to reconnect after a week: the app is still in Testing; publish it.
- "The sheet is not shared with you yet": the member must confirm the sharing question before the organiser enters the code.
- Quotas: Google limits reads and writes per user per minute. The app batches writes and reads a member's sheet only when its revision counter changed, which is far below the limits for a family.

## Privacy
Tokens are kept in the platform's secure storage on each device. The app has no server in this mode, and nothing is sent anywhere except to Google. See `docs/PRIVACY.md`.
