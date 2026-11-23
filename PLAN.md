# ConcentrationMaxx — build plan

An iPhone app that blocks social media for a time you set. Ending a block early means typing your password three times. Written in Swift, shipped through TestFlight.

Plan written 2026-11-23. Section 10 lists the open risks that only a test on a real iPhone can settle.

## 1. What you asked for and how each part works

| Requirement | How it is built |
|---|---|
| Block TikTok, Instagram, X/Twitter, Reddit, Snapchat for a set time | Apple's Screen Time API (`FamilyControls`, `ManagedSettings`, `DeviceActivity`). The app puts a system "shield" over the chosen apps until the timer ends. |
| Messaging apps blocked too, but unblockable | Messaging apps are a second, separate group. Each block has an "also block messaging" switch, and during a block one password entry unblocks messaging only. |
| Never block phone calls | The Phone app cannot be shielded by this API and is never in any group. FaceTime and Apple Messages stay in iOS's "Always Allowed" list unless you remove them yourself. |
| Password three times before unlocking | "End block early" asks for the password 3 times in a row (adjustable 3–5). A wrong entry restarts the count. No paste, no AutoFill, no Face ID. |
| Block all notifications | Notifications from shielded apps are silenced by iOS while the shield is up. For every other app, iOS only allows this through Focus / Do Not Disturb, so the app ships a Shortcuts action that starts a block and can be chained with "turn on Do Not Disturb". |
| Instagram without Reels (optional) | A built-in web view of instagram.com with Reels requests blocked and the Reels tab removed. Off by default; each person turns it on in Settings. |
| Login details in a non-relational DB | A small Swift server (Vapor) storing accounts in MongoDB. It holds a username and a bcrypt password hash, nothing else. |
| TestFlight for you and friends | GitHub Actions builds, signs and uploads on a macOS runner, so no Mac is needed. |

## 2. Limits set by iOS

These are platform rules, not choices. Each one shapes the design.

1. **Apps are picked, not hardcoded.** iOS hides other apps' identities from us. During setup each person picks their apps in Apple's own picker, once. The setup screen lists what to tick (TikTok, Instagram, X, Reddit, Snapchat, then messaging apps).
2. **TestFlight needs Apple's approval for this API.** The "Family Controls (Distribution)" entitlement must be requested per bundle ID, and we have four. Developers report waits from a few days to over a month in 2026. Nothing reaches TestFlight until it is granted, so this is the first thing to do (section 9).
3. **Blocks are at least 15 minutes.** The scheduling API rejects shorter intervals.
4. **An app cannot switch on Do Not Disturb or mute other apps' notifications.** Hence the Shortcuts action above.
5. **A determined person can still get out.** Settings → Screen Time lets the phone's owner revoke the app's access with the device passcode. Strict mode (section 4) closes the cheaper exits: deleting the app and changing the clock.
6. **Blocking an app also blocks its website.** Shielding Instagram shields instagram.com in Safari too. Useful in general, but it is the main risk for the Reels-free feature (section 6).

## 3. Architecture

### iOS targets (deployment target iOS 17.0, SwiftUI, no third-party dependencies)

| Target | Bundle ID | Job |
|---|---|---|
| App | `com.malachitopp.concentrationmaxx` | All screens, starts and ends blocks |
| DeviceActivityMonitor extension | `…concentrationmaxx.monitor` | Lifts the shield when the timer ends, even if the app is closed |
| ShieldConfiguration extension | `…concentrationmaxx.shieldconfig` | Custom "Blocked until 17:30" screen over blocked apps |
| ShieldAction extension | `…concentrationmaxx.shieldaction` | Handles the shield's button; also lifts an expired block if the monitor missed it |

App Group `group.com.malachitopp.concentrationmaxx` shares the session record between the app and extensions. The bundle ID prefix lives in one place in `ios/project.yml` so it can be changed before the IDs are registered with Apple.

### Blocking

- Authorisation: `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
- Two saved `FamilyActivitySelection`s: **social** and **messaging**. Each maps to its own named `ManagedSettingsStore`, so unblocking messaging is "clear one store".
- Shield covers picked apps, picked categories and picked websites (`shield.applications`, `shield.applicationCategories`, `shield.webDomains`). The shield takes at most 50 individual apps; the picker's categories cover larger sets.
- No use of `webContent.blockedByFilter = .specific(...)`: developers report it failing in Safari on iOS 26 and blocking unrelated content on 26.6.
- Starting a block: the app applies the shields immediately, saves a session record `{id, start, end, messagingBlocked, strictMode}` to the App Group, and registers a non-repeating `DeviceActivitySchedule` ending at `end`.
- Ending on time, three independent paths because the monitor callback is not fully reliable:
  1. Monitor extension `intervalDidEnd` clears both stores.
  2. The app checks for an expired session every time it comes to the foreground.
  3. The ShieldAction extension clears an expired block when the shield button is tapped.
  A local notification at the end time tells the person the block is over.
- Failure mode is "stays blocked until the app is opened", never "silently unblocked".
- Sessions run 15 minutes to 24 hours. A running block can be extended but not shortened.

### Strict mode (per-user setting, on by default)

During a block: `application.denyAppRemoval = true` (no deleting apps to escape) and `dateAndTime.requireAutomaticDateAndTime = true` (no moving the clock forward). Both are cleared when the block ends.

### Passwords and unlocking

- The password is the account password, minimum 10 characters.
- At sign-in the app stores a PBKDF2-HMAC-SHA256 verifier (random salt, high iteration count) in the Keychain. Unlock checks happen against it on the device, so unlocking works with no signal and the server can be asleep.
- Unlock flow: N consecutive correct entries (N = 3 by default, 3–5 in Settings, changeable only when no block is running). Wrong entry resets to step 1. Five wrong entries lock the flow for 5 minutes.
- The field is a UIKit-backed secure field with paste, AutoFill and biometrics disabled.
- Forgotten password during a block: the block runs to its end. Logging out and changing the password are disabled during a block.

## 4. Screens

1. **Onboarding:** welcome → create account / log in → Screen Time permission → pick social apps → pick messaging apps → notification permission → optional features.
2. **Home:** duration (15m, 30m, 1h, 2h, 4h, custom), "also block messaging apps" switch, Start.
3. **Active block:** countdown and end time, "Unblock messaging apps" (1 password entry), "Instagram (no Reels)" if enabled, "End block early" (3 password entries).
4. **Unlock:** step 1 of 3, 2 of 3, 3 of 3.
5. **Settings:** edit block lists (locked during a block), Reels-free Instagram on/off, password entries required, strict mode, account (change password, log out, delete account), Do Not Disturb shortcut instructions.

Shortcuts: a `StartBlockIntent` App Intent with a duration parameter, so one shortcut can turn on Do Not Disturb (with calls still allowed) and start a block.

## 5. Backend

Swift on the server too: **Vapor 4 + MongoKitten** against **MongoDB Atlas** (free tier). MongoDB stopped developing its own Swift driver and points to MongoKitten. A server is required because the app must never contain the database credentials, and Atlas's serverless Data API has been shut down.

### Data

`users` collection: `{ _id, username (unique, lowercase), passwordHash (bcrypt), createdAt, updatedAt }`. No email, no usage data, no app lists.

### API

| Method | Path | Body | Result |
|---|---|---|---|
| POST | `/v1/auth/register` | `username, password, inviteCode` | `201 {token, user}` |
| POST | `/v1/auth/login` | `username, password` | `200 {token, user}` |
| GET | `/v1/me` | — (Bearer token) | `200 {user}` |
| POST | `/v1/me/password` | `currentPassword, newPassword` | `204` |
| DELETE | `/v1/me` | `password` | `204` |
| GET | `/health` | — | `200 {status}` |

Errors are `{error: {code, message}}` with 400 / 401 / 403 / 409 / 429.

### Security

- Registration needs a shared **invite code**, because the repo and server address are public.
- Bcrypt hashes, JWT (HS256, 30 days) kept in the iOS Keychain, HTTPS only.
- Rate limiting on auth routes; login failures return one generic message.
- `MONGODB_URI`, `JWT_SECRET`, `INVITE_CODE` come from environment variables. Only `.env.example` is committed.

### Device-only fallback

If the app is built with no `API_BASE_URL`, account creation makes a password that lives only on that phone. This keeps the app usable before the server is deployed.

## 6. Instagram without Reels

Off by default. When on, the app offers an in-app Instagram that keeps feed and messages.

- `WKWebView` on `https://www.instagram.com/` with a persistent data store so the login sticks.
- Three layers remove Reels:
  1. A `WKContentRuleList` blocks network requests to Reels endpoints.
  2. The navigation delegate cancels loads of `/reels/`, `/reel/` and `/explore/`.
  3. An injected script hides the Reels and Explore tabs and bounces in-page route changes back to the feed, because Instagram navigates without page loads.
- The rules live in bundled JSON and JS files so they can be updated when Instagram changes its site. That will happen, and this feature will need occasional maintenance.
- The feed itself is not filtered. Video posts in the feed still play.

### The risk, and the fallback

While the native Instagram app is shielded, iOS may also shield instagram.com inside our web view. This cannot be tested without a real device. So Instagram can be blocked by either of two strategies, switchable in a debug menu:

- **Shield (default):** Instagram is shielded like every other app.
- **Hide:** Instagram is taken out of the shield and hidden with `application.blockedApplications` by bundle ID, which may not carry the website block with it. This needs one extra setup step where the person picks Instagram on its own.

If neither works on a real device, the feature cannot coexist with blocking the native app and we will have to rethink it.

## 7. Build and release without a Mac

- **XcodeGen** (`ios/project.yml`) describes the project; the `.xcodeproj` is generated in CI and never committed.
- `ios-ci.yml` on every push: generate, build for the simulator unsigned, run unit tests. This needs no secrets and is the compile check for all development.
- `server-ci.yml` on every push: `swift build` and `swift test` on Linux with a MongoDB service container.
- `testflight.yml`, run by hand: archive with automatic signing through an App Store Connect API key, upload to TestFlight. Build number is the run number. A second mode exports a development-signed `.ipa` for registered devices, for testing before Apple grants the distribution entitlement.
- macOS runners are free for public repos.

## 8. Repo layout

```
PLAN.md
README.md                 setup guide
ios/
  project.yml
  App/                    SwiftUI app
  Shared/                 session store, block controller (app + extensions)
  Extensions/
    DeviceActivityMonitor/
    ShieldConfiguration/
    ShieldAction/
  Tests/
server/
  Package.swift
  Sources/  Tests/
  Dockerfile
  .env.example
.github/workflows/
  ios-ci.yml  server-ci.yml  testflight.yml
```

## 9. What only the account owner can do

In order. Step 1 has the longest wait, so start it first.

1. **Apple Developer portal:** register the four bundle IDs and the App Group from section 3, with the App Groups and Family Controls capabilities. Then submit a **Family Controls (Distribution)** request for each of the four IDs at <https://developer.apple.com/contact/request/family-controls-distribution>.
2. **App Store Connect:** create the app record for the main bundle ID. Create an API key (Users and Access → Integrations, Admin role).
3. **GitHub repo secrets:** `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`. Repo variable: `API_BASE_URL`.
4. **Backend:** create a free MongoDB Atlas cluster, deploy the server's Docker image to a host, set the three environment variables.
5. **TestFlight:** run the workflow, then add friends as external testers. The first build goes through Apple's beta review.

## 10. Open risks, to check on a real iPhone

| Risk | What to check | If it fails |
|---|---|---|
| Reels-free web view is shielded along with the Instagram app | Start a block, open in-app Instagram | Switch to the "Hide" strategy in the debug menu |
| Shielded apps still show notifications | Have a friend message you on a blocked app | Fall back on the Do Not Disturb shortcut |
| Monitor extension misses the end of a block | Let a 15-minute block run out with the app closed | Backups 2 and 3 in section 3 still lift it |
| Apple Messages cannot be shielded | Add Messages to the messaging group | It must first be removed from Screen Time's Always Allowed list |
| Beta review objects to wrapping Instagram's website | First external TestFlight build | Ship that build with the feature compiled out |

## 11. Build order

1. Project skeleton, CI green on an empty app.
2. Core blocking: permission, pickers, sessions, shields, all three extensions.
3. Server, accounts, local verifier, the three-entry unlock.
4. Messaging unblock, strict mode, end notification, Shortcuts action.
5. Reels-free Instagram with both strategies.
6. TestFlight workflow and the README setup guide.
