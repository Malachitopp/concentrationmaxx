# ConcentrationMaxx

An iPhone app that blocks social media for a time you choose. Ending a block early means typing your password several times in a row (3 by default). Built on Apple's Screen Time API, written in Swift (app and server), and shipped through TestFlight by GitHub Actions, so no Mac is needed.

[PLAN.md](PLAN.md) is the design: what each part does and why. This README is the setup guide.

```
ios/                      iPhone app (XcodeGen project, generated in CI)
  project.yml             targets, bundle IDs, App Group, capabilities
  App/                    the app: Sources (SwiftUI), Core (testable logic), Resources
  Shared/                 block engine used by the app and the three extensions
  Extensions/             DeviceActivityMonitor, ShieldConfiguration, ShieldAction
  Tests/                  unit tests (run in CI on a simulator)
  scripts/                CI helpers
server/                   account server: Vapor 4 + MongoKitten, Dockerfile, .env.example
.github/workflows/        ios-ci.yml, server-ci.yml (every push), testflight.yml (by hand)
```

## Contents

1. [What is already done for this repo](#1-what-is-already-done-for-this-repo)
2. [Deploy the account server](#2-deploy-the-account-server) (to do)
3. [Ship a build to TestFlight](#3-ship-a-build-to-testflight) (to do)
4. [First run on your iPhone, and what to check](#4-first-run-on-your-iphone-and-what-to-check)
5. [Apple setup, for reference or for a fork](#5-apple-setup-for-reference-or-for-a-fork)
6. [Optional: development builds without TestFlight](#6-optional-development-builds-without-testflight)
7. [Working on the code without a Mac](#7-working-on-the-code-without-a-mac)
8. [Troubleshooting](#8-troubleshooting)
9. [What is stored, and where](#9-what-is-stored-and-where)

---

## 1. What is already done for this repo

These steps from PLAN.md section 9 were completed on 2026-11-23. Nothing here needs repeating unless you fork the repo onto another Apple team (then follow [section 5](#5-apple-setup-for-reference-or-for-a-fork)).

| Step | State |
|---|---|
| Latest Apple Developer Program License Agreement | Accepted |
| Family Controls (Distribution) entitlement | Assigned to the team |
| App Group `group.com.malachitopp.concentrationmaxx` | Registered |
| App IDs `com.malachitopp.concentrationmaxx`, `.monitor`, `.shieldconfig`, `.shieldaction` | Registered, each with App Groups (that group) and Family Controls (Distribution) |
| App Store Connect app record "ConcentrationMaxx" | Created |
| App Store Connect team API key, Admin role | Created |
| GitHub secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` | Set |
| GitHub variable `API_BASE_URL` | **Not set yet**: no server is deployed (section 2) |

What is left for you: deploy the server (section 2), then add testers (section 3). Until `API_BASE_URL` is set, builds use device-only accounts: the password lives only on that iPhone (PLAN.md section 5). That is fine for trying the app yourself.

---

## 2. Deploy the account server

The server stores accounts (a username and a bcrypt hash, nothing else) in MongoDB. It is one small Docker container. You need three things: a MongoDB Atlas database, a host that runs the container with HTTPS, and three environment variables.

### 2.1 Create the database (MongoDB Atlas, free)

Atlas's free cluster (formerly called M0) is free for good: 512 MB, shared CPU, no credit card. 512 MB is far more than a few hundred accounts need.

1. Sign up at <https://www.mongodb.com/cloud/atlas/register>.
2. **Create a cluster:** Project overview → **Create** → pick **M0 / Free** → any provider and a region near your host (Frankfurt or Washington D.C. are good matches for the hosts below) → name it (it cannot be renamed) → **Create**.
3. **Create a database user** in the Security Quickstart that opens (or later under Security → Database & Network Access → Database Users → Add New Database User): authentication method **Password**, a username such as `cmx-server`, and click **Autogenerate Secure Password**. Copy the password somewhere safe. Prefer letters and digits only: other characters must be percent-encoded in the connection string (`@` becomes `%40`). Give it the built-in role that allows reading and writing any database.
4. **Allow the server to connect:** Security → Database & Network Access → **IP Access List** → **Add IP Address** → enter `0.0.0.0/0` → **Confirm**. Free hosts do not have fixed outgoing IP addresses, so the database has to accept connections from anywhere. Atlas warns about this, rightly: from then on the database user's password is the only thing protecting the data, which is why it should be long and random. Atlas emails you when a `/0` entry is added.
5. **Copy the connection string:** Clusters → **Connect** → **Drivers** → copy the string under "Use this connection string in your application". It looks like
   `mongodb+srv://cmx-server:<db_password>@cluster0.abcde.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0`.
   Replace `<db_password>` with the password. You may put the database name after `.net/`, as in `...mongodb.net/concentrationmaxx?retryWrites=...`; without one the server uses `concentrationmaxx`.

Atlas pauses a free cluster after 30 days without any connection. If nobody uses the app for a month, open Atlas and click **Resume**.

### 2.2 Choose the two secrets

- `JWT_SECRET`: random text of at least 32 characters, used to sign login tokens. In Windows PowerShell:
  ```powershell
  $bytes = New-Object byte[] 48; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes); [Convert]::ToBase64String($bytes)
  ```
  Changing it later logs every phone out of the server; unlocking blocks keeps working, because that is checked on the phone.
- `INVITE_CODE`: any code you give only to your friends, for example `friends-2026-xyz`. The repo and the server address are public, so new accounts need it.

### 2.3 Run the container on a host

The container is built from [server/Dockerfile](server/Dockerfile). Any host that can build a Dockerfile from a GitHub repo, give it a public HTTPS address and set environment variables will do. The server listens on the port in `$PORT` (8080 if unset) and answers `GET /health` with `{"status":"ok"}`, which hosts can use as a health check.

Environment variables (see [server/.env.example](server/.env.example)):

| Name | Value |
|---|---|
| `MONGODB_URI` | the Atlas connection string from 2.1 |
| `JWT_SECRET` | from 2.2 |
| `INVITE_CODE` | from 2.2 |
| `CLIENT_IP_HEADER` | optional, `X-Forwarded-For` on the hosts below, so rate limits apply per visitor instead of per proxy |
| `BCRYPT_COST` | optional, default 12. On a very small instance, 11 halves the time a login takes |

The server refuses to start if any of the first three is missing or `JWT_SECRET` is shorter than 32 characters; the host's log then says which one.

Free-tier terms checked on 2026-11-23:

**Option A: Render (free, no credit card).** Free web services sleep after 15 minutes without traffic and take about a minute to wake up; 750 free hours a month, which covers one service running all month. The app waits up to 90 seconds for the server and says so, so a sleeping server only makes the first login slow.

1. Sign up at <https://render.com> with your GitHub account.
2. **New** → **Web Service** → connect the `concentrationmaxx` repository.
3. Language **Docker**, Branch `main`, **Root Directory** `server` (the Dockerfile path is then `./Dockerfile`).
4. Instance type **Free**.
5. Add the environment variables above. Render sets `PORT` itself (10000); the server reads it.
6. Under Advanced, set **Health Check Path** to `/health`.
7. **Create Web Service**. The first build takes 10 to 15 minutes. Your address is shown at the top, for example `https://concentrationmaxx.onrender.com`.

**Option B: Google Cloud Run (needs a billing account with a card).** Its free quota (2 million requests and plenty of CPU time a month) is far above what a few friends use, it starts in a second or two, and it can be deployed entirely from the browser with Cloud Shell, so nothing is installed on your PC. Create a project with billing enabled at <https://console.cloud.google.com>, open Cloud Shell (the `>_` icon), and run:

```bash
git clone https://github.com/Malachitopp/concentrationmaxx.git && cd concentrationmaxx
gcloud run deploy concentrationmaxx --source server --region europe-west1 --allow-unauthenticated \
  --set-env-vars "MONGODB_URI=...,JWT_SECRET=...,INVITE_CODE=...,CLIENT_IP_HEADER=X-Forwarded-For"
```

Put the connection string in quotes exactly as copied. If it contains a comma, use `--env-vars-file` with a small YAML file instead.

Koyeb, often suggested for this, stopped offering a free plan to new accounts in February 2026. Fly.io's free plan needs a card on file after a 7-day trial.

### 2.4 Check it, then point the app at it

1. Open `https://<your address>/health` in a browser. It should say `{"status":"ok"}`. (On Render, the first visit after a while takes up to a minute.)
2. In GitHub: the repo → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab → **New repository variable**. Name `API_BASE_URL`, value your address with `https://` and nothing after it, for example `https://concentrationmaxx.onrender.com`.
3. Run the TestFlight workflow again (section 3). New builds create accounts on the server. A phone that set up a device-only password keeps it until you log out in Settings (outside a block) and create a server account.

---

## 3. Ship a build to TestFlight

### 3.1 Run the workflow

1. GitHub → the repo → **Actions** → **testflight** → **Run workflow**.
2. Leave **mode** on `testflight` and **Include Reels-free Instagram** ticked, then **Run workflow**.
3. It takes about 15 to 25 minutes: build, sign, check the entitlements, upload, then wait for Apple's processing. The build number is the run number.

How signing works, so the log makes sense: the archive is built unsigned and signed ad hoc with its entitlements; the export then re-signs it with an Apple-managed distribution certificate and App Store profiles that Xcode creates through the API key. No certificate or profile is stored anywhere, and no Mac or registered device is needed.

### 3.2 Test it yourself first (internal testing)

1. Install **TestFlight** from the App Store on your iPhone, signed in with the Apple ID of your developer account.
2. <https://appstoreconnect.apple.com> → **Apps** → ConcentrationMaxx → **TestFlight**. The build appears under iOS builds; once processing is done it may show a yellow warning until it has been added to a group.
3. Under **Internal Testing**, create a group (for example "Me"), add yourself and add the build. You get an email and the build appears in the TestFlight app.

Export compliance is answered by the app itself (`ITSAppUsesNonExemptEncryption = NO`: it only uses HTTPS and standard password hashing), so builds do not stop at "Missing Compliance".

### 3.3 Invite friends (external testing)

External testers need Apple's beta review once per version. Before the first submission:

1. **TestFlight → Test Information** (left sidebar, under Additional): fill in the **Beta App Description** (required), a **Feedback Email**, and the **Beta App Review Information** contact (name, email, phone in `+44…` form).
2. **Sign-in information** (same page): the app needs an account, so tick "Sign-in required" and enter a demo account. Create it yourself in the app first (with your invite code) once the server is running, and keep it working for the whole review. In **Review Notes**, explain how to test, for example: "Allow Screen Time access (needs a passcode), pick any app in the picker, start a 15-minute block, then End block early and type the demo password 3 times. Screen Time features only work on a real device."
3. A privacy policy URL is optional for TestFlight but recommended; a short page saying what section 9 below says is enough.
4. **External Testing** → create a group → add the build → **Submit for Review**. The first build gets a full review; later builds of the same version often go through without one.
5. Add testers by email, or turn on a **public link** and send it to friends. Up to 10,000 external testers.

Builds stay installable for 90 days. If the review objects to the in-app Instagram (PLAN.md section 10), run the workflow with **Include Reels-free Instagram** unticked and submit that build.

---

## 4. First run on your iPhone, and what to check

The app walks through: account → Screen Time access (Face ID or passcode; the iPhone must have a passcode and be signed in to iCloud) → pick social apps → pick messaging apps → notifications → options. Then start a 15-minute block and try it.

Screen Time features cannot be tested on a simulator, so these are the checks that matter on the first real build (PLAN.md section 10). **Settings → Advanced → Diagnostics** shows what the extensions did and when; the extensions cannot be watched any other way without a Mac.

| Check | How | Look for |
|---|---|---|
| Blocked apps show the custom screen | Start a block, open TikTok | "Blocked until …" with your end time |
| The block ends with the app closed | Start a 15-minute block, close ConcentrationMaxx, wait | Diagnostics: "monitor … Block over, shields lifted". If not, opening the app or tapping the shield's button still ends it |
| End early | End block early, type the password 3 times | A wrong entry restarts at step 1; 5 wrong entries lock the screen for 5 minutes |
| Messaging | Block with "also block messaging", then Unblock messaging apps | One correct entry frees messaging only |
| Notifications from blocked apps | Have a friend message you on a blocked app | If they still arrive, use the Do Not Disturb shortcut (Settings → Do Not Disturb) |
| Strict mode | During a block, try to delete an app or change the clock | Both refused |
| Apple Messages | Add Messages to the messaging list | It must first be removed from Screen Time's "Always Allowed" list |
| Reels-free Instagram | Turn it on in Settings, start a block, open "Instagram (no Reels)" | If iOS blocks instagram.com there too, switch Settings → Advanced → Instagram strategy to "Hide" and pick Instagram on its own |
| "Hide" strategy | With Hide on, start a block | The Instagram icon must disappear from the Home Screen. If it stays, Hide does not work under this kind of Screen Time access and leaves Instagram unblocked: switch back to Shield |
| Shortcuts | In Shortcuts, add "Start a Block" from ConcentrationMaxx | A block starts without opening the app |

Please send back anything that fails, with a screenshot of Diagnostics if it is relevant.

---

## 5. Apple setup, for reference or for a fork

**For this repo all of this is done (section 1).** Keep it as reference, or follow it if you fork the repo onto another Apple team. If you fork, first change `CMX_BUNDLE_ID` in [ios/project.yml](ios/project.yml), the one place the bundle ID prefix lives, so the IDs below are yours.

1. **Accept the latest Program License Agreement** at <https://developer.apple.com/account>. Until you do, Certificates, Identifiers & Profiles, App Store Connect and its API are locked.
2. **Request Family Controls (Distribution)** at <https://developer.apple.com/contact/request/family-controls-distribution>. It is one form for the whole team: Apple fills in your name, email and Team ID, and you accept the terms and click Get Entitlement. Apple does not say how long the grant takes. Account → Membership details shows "Assigned" once it is granted. (Apple's documentation page still talks about one request per extension; the form no longer asks for bundle IDs. If Apple asks for more, file those.)
3. **Register the App Group:** Certificates, Identifiers & Profiles → Identifiers → **+** → App Groups → description "ConcentrationMaxx", identifier `group.<your bundle ID>`.
4. **Register four App IDs:** Identifiers → **+** → App IDs → App, explicit bundle ID, for `<bundle ID>`, `<bundle ID>.monitor`, `<bundle ID>.shieldconfig` and `<bundle ID>.shieldaction`. On each, enable **App Groups** (then Configure → tick the group) and **Family Controls (Distribution)**.
5. **App Store Connect → Apps → +** → New App: platform iOS, a name, a primary language, bundle ID `<bundle ID>`, any SKU.
6. **API key:** App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**. The first time, the Account Holder has to click **Request Access** and accept the terms. Then **Team Keys** → **Generate API Key** (or **+**), any name, Access **Admin** (Xcode's cloud-managed signing refuses lesser roles with "Cloud signing permission error") → Generate. **Download the .p8 file; Apple lets you download it only once.** Note the **Key ID** (in the key's row) and the **Issuer ID** (above the list).
7. **GitHub secrets:** the repo → Settings → Secrets and variables → Actions → **New repository secret**, four times:

   | Secret | Value |
   |---|---|
   | `APPLE_TEAM_ID` | the 10-character Team ID from developer.apple.com → Account → Membership details |
   | `ASC_KEY_ID` | the key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_PRIVATE_KEY` | the whole text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines (open it in Notepad and copy everything) |

   Never commit the `.p8` file or paste these values anywhere public. `.gitignore` already excludes `.p8` files and `.env`.

---

## 6. Optional: development builds without TestFlight

`testflight.yml` has a second mode, `development-ipa`, that makes a development-signed `.ipa` for registered iPhones. TestFlight is simpler, so you only need this to test a build without uploading it. It needs two things this repo does not have yet:

1. **Family Controls (Development)** ticked on the four App IDs (Certificates, Identifiers & Profiles → Identifiers → each ID). Only the Distribution variant is ticked now, so a development build would be refused for lacking the entitlement.
2. **Your iPhone registered** as a device. To find its UDID on Windows, connect it to the **Apple Devices** app (Microsoft Store), select it, and click the line under its name until "UDID" shows; in iTunes for Windows, click "Serial Number" on the Summary page until it shows "Identifier (UDID)". Then Certificates, Identifiers & Profiles → Devices → **+**.

Then run the workflow with mode `development-ipa`, download the `.ipa` from the run page (it is kept for one day only: artifacts of a public repo can be downloaded by any signed-in GitHub user, and a development `.ipa` lists the registered devices), and delete the artifact once you have it. To install it from Windows: [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) (free; needs iTunes from apple.com; `pymobiledevice3 apps install ConcentrationMaxx-…-development.ipa`) or iMazing (free trial: Tools → Install Custom Package). Avoid tools that re-sign the app with your Apple ID, such as Sideloadly's default mode: re-signing drops the Family Controls entitlement. On the iPhone, turn on Settings → Privacy & Security → **Developer Mode** (it appears after a development app has been installed), restart, and confirm.

Each development run leaves an "Apple Development: Created via API" certificate in your account. Revoke old ones in Certificates, Identifiers & Profiles → Certificates when the list gets long; a revoked certificate stops the builds signed with it from launching. TestFlight runs create no such certificate.

---

## 7. Working on the code without a Mac

GitHub Actions is the compiler. Every push runs:

- **ios-ci**: generates the Xcode project with XcodeGen, builds the app and its extensions for the simulator unsigned, runs the unit tests, and archives a Release build for devices (with and without the Reels-free feature) up to the point where Apple's signing takes over, including the entitlement checks.
- **server-ci**: `swift build` and `swift test` on Linux, with a MongoDB service container for the repository tests, plus a Docker image build.

Watch a run with `gh run watch <id>` and read failures with `gh run view <id> --log-failed`.

The server also runs locally in Docker:

```powershell
cd server
docker run --rm -v "${PWD}:/work" -w /work swift:6.3-noble swift test
docker build -t concentrationmaxx-server .
docker run --rm -p 8080:8080 --env-file .env concentrationmaxx-server   # copy .env.example to .env first
```

Things that may need updating over time:

- **Instagram's website** changes now and then. The Reels-free rules live in [ios/App/Resources/Instagram](ios/App/Resources/Instagram): `reels-rules.json` (blocked paths), `reels-content-rules.json` (blocked requests) and `reels-filter.js` (in-page navigation). The unit tests check all three.
- **Xcode on the runners:** `XCODE_VERSION` at the top of `ios-ci.yml` and `testflight.yml`. App Store Connect currently requires the iOS 26 SDK or later; `ios/scripts/select-xcode.sh` fails the run if the SDK is older.
- **The bundle ID prefix:** only `CMX_BUNDLE_ID` in `ios/project.yml`.

---

## 8. Troubleshooting

**testflight.yml**

| Message | Meaning and fix |
|---|---|
| Missing repository secrets | One of the four secrets is not set (section 5, step 7) |
| The App Store Connect API key was not accepted | Wrong Key ID or Issuer ID, a revoked key, or `ASC_PRIVATE_KEY` missing the BEGIN/END lines |
| Cloud signing permission error | The API key is not an Admin team key |
| Provisioning profile … doesn't include the com.apple.developer.family-controls entitlement | Family Controls (Distribution) is not enabled on that App ID (development mode: Family Controls (Development)) |
| No profiles for … were found / App ID not found | One of the four App IDs is missing or has a different bundle ID |
| … is not signed with the App Group | The App Group is not assigned to that App ID |
| The bundle version must be higher than the previously uploaded version | A build number was used before; run the workflow again (a new run gets a new number) |
| App Store Connect marked the build INVALID | Apple emails the reason to the account holder |

**Server**

| Symptom | Fix |
|---|---|
| Container exits at start, log names an environment variable | Set it on the host (section 2.3) |
| Log shows a MongoDB authentication error | Wrong database user or password in `MONGODB_URI`, or special characters not percent-encoded |
| Log shows a connection timeout to MongoDB | Atlas IP Access List lacks `0.0.0.0/0`, or the cluster is paused |
| The app says the server did not answer in time | A sleeping free instance; try again after a minute |

**App**

| Symptom | Fix |
|---|---|
| "Screen Time access is off" | Settings → Screen Time must be on, the iPhone needs a passcode and an iCloud account; then allow access again in the app |
| An app stays blocked after the end time | Open ConcentrationMaxx once, or tap the shield's button: both lift an expired block. Diagnostics shows whether the monitor ran |
| Forgot the password during a block | The block runs until it ends. That is by design |

---

## 9. What is stored, and where

- **Server (MongoDB):** username, bcrypt hash of the password, created and updated times. No email, no usage data, no app lists. Delete account (Settings, outside a block) removes the record.
- **iPhone, Keychain:** the login token and a PBKDF2-HMAC-SHA256 verifier of the password (random salt, 600,000 iterations), so unlocking works offline. Never the password itself.
- **iPhone, App Group:** the running block (start, end, messaging and strict mode flags), the app lists as opaque Screen Time tokens, and a short diagnostics log. None of it leaves the phone.
- No analytics, tracking or third-party SDKs.
