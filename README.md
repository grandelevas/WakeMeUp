# WakeMeUp

An iPhone alarm app in the spirit of Clock → Alarms, plus groups, your own sounds, a one-tap link to a song, and alarms that another person can set after you let them.

The working names are **Remind me of** and **Przypomnij mi o**. The home-screen name is WakeMeUp. The interface is SwiftUI, in English and Polish.

There is no Mac in the loop. GitHub Actions `macos-26` builds the app, runs the tests, and takes Simulator screenshots. A second workflow signs a Release build and uploads it to TestFlight once the Apple secrets below exist. That workflow is expected to fail until then.

## Features

- Create, edit, delete, and toggle alarms. Each alarm has a time, label, repeat days, snooze (default 9 minutes), and a sound.
- Alarms are scheduled with **AlarmKit** (iOS 26). AlarmKit is the system API that can ring on the Lock Screen through Silent and Focus, the same class of alert as the built-in Clock app. There is no AlarmKit entitlement. The only requirement is `NSAlarmKitUsageDescription`, which is already in the Info.plist (English and Polish).
- If the person denies AlarmKit, the app falls back to a time-sensitive local notification with the same sound and with Stop, Snooze, and Play my song actions. Those notifications **do not** ring through the silent switch. The Settings screen says so.
- **Groups.** A group has one switch. Turning it off disables every alarm in the group and remembers which ones were on. Turning it back on restores that. Deleting a group keeps the alarms.
- **Sounds.** Five tones ship in the app: Classic, Chime, Rise, Pulse, Soft Bell. They are synthesized by `scripts/generate-sounds.py` and dedicated to the public domain (CC0). See `WakeMeUp/Sounds/LICENSE.txt`. A person can import an audio file from Files, trim it to at most 30 seconds, and use that clip. AlarmKit and notification sounds both require a short file in the bundle or in `Library/Sounds`.
- **Favorite song.** An alarm can store a Spotify, YouTube, or Apple Music link. iOS will not open another app by itself when an alarm fires. The alarm alert's second button is **Play my song**. That button stops the alarm and opens the link. The in-app ringing screen has the same button.
- **Remote alarms.** Person A can add, change, cancel, disable, or ring an alarm on person B's phone only after B accepts an invite. Either person can revoke. The rules live in `PermissionCenter` and `RemoteCommandApplier` and are covered by unit tests. A remote command cannot delete or edit an alarm the sender did not create.

Until CloudKit is configured, Sharing runs an on-device preview: a simulated friend goes through the same invite, accept, and command checks, and a "ring now" from that friend really schedules an alarm on this phone. The screen says that it is a preview.

## AlarmKit and the song button

AlarmKit's alert has a system Stop button and **one** optional second button.

- No song link, snooze on: the second button is Snooze. Snooze length is the AlarmKit post-alert countdown. A widget extension draws that countdown, which AlarmKit expects whenever a countdown presentation is used.
- Song link set: the second button is Play my song (`secondaryButtonBehavior: .custom`). Snooze is still on the in-app ringing screen. One system alert cannot show both.

Play my song is a `LiveActivityIntent` (`PlaySongIntent`) with `openAppWhenRun`. It stops the AlarmKit alarm and opens the URL. The same hand-off is written to the app group `group.<bundle id>` so a tap that only brings WakeMeUp forward still opens the song.

## Remote alarms and CloudKit

The transport is CloudKit, not a server you have to host.

The phone that rings owns a private CloudKit zone named `WakeMeUp` and a `CKShare` on one root record. The invite is the share URL. The other person accepts the share and writes command JSON onto that record. The owner subscribes to the zone with a content-available push. When the push arrives, the app applies any new commands and schedules them with AlarmKit (or the notification fallback).

Why not the public database: it does not push. The other phone would only see commands the next time the app was opened, which is too late for an alarm.

Why not Firebase: it needs a project, a server key, and another privacy review, and a push still cannot run arbitrary work for long. CloudKit is enough if both people use iCloud.

Limits, because this is iOS:

- The silent push is **not guaranteed**. It can be delayed, dropped under Low Power Mode, or never delivered if the app was force-quit. A remote alarm for tomorrow is fine if the phone is online at some point before it. **Ring now** only rings when the push actually wakes the app, and it may be late.
- Both people need to be signed into iCloud.
- The container id in `WakeMeUp/WakeMeUpConfig.plist` must be set, and the Release entitlements must list the same container. Debug builds used by CI do not include the iCloud or push entitlements, so the Simulator tests do not need an Apple Developer account.
- Development CloudKit creates the schema when the first record is saved. Before a production TestFlight build, deploy the schema in the CloudKit console (record type `WMRoot`, fields `grantJSON` and `commandsJSON`).

## Architecture

```
WakeMeUp/Domain        pure Swift. Scheduling, groups, permissions, song links, trim math.
WakeMeUp/Services      AlarmKit, notifications, audio trim, CloudKit, JSON store.
WakeMeUp/UI            SwiftUI. AppModel is @Observable.
Shared                 AlarmMetadata compiled into the app and the widget.
WakeMeUpWidget         Live Activity for the snooze countdown.
WakeMeUpTests          unit tests for the domain. No AlarmKit required.
```

`project.yml` is the source of the Xcode project. CI runs [XcodeGen](https://github.com/yonaskolb/XcodeGen) and does not commit `WakeMeUp.xcodeproj`.

`AlarmSyncPlan` decides what to schedule or cancel. `AlarmCoordinator` tries AlarmKit first and uses notifications only when AlarmKit refuses (almost always because access was denied).

Persistence is one JSON file in Application Support. Dates are ISO-8601.

## Tests and CI

Unit tests cover:

- next fire time for one-shot and weekly alarms, including "this exact minute waits until tomorrow"
- group on/off memory, alarms added while a group is off, deleting a group
- the schedule/cancel diff
- invite, accept, reject your own invite, revoke, and the rule that a stranger cannot revoke
- remote create and cancel, and the refusal to overwrite a local alarm
- Spotify, YouTube, and Apple Music link parsing
- the 30-second trim window
- actually trimming a generated WAV

On every push and pull request, `.github/workflows/ci.yml`:

1. Selects Xcode 26.6 (or 26.5 if 26.6 is not on the image) on `macos-26`.
2. Installs XcodeGen and generates the project.
3. Picks the newest installed iPhone simulator (iPhone 17 preferred).
4. Runs `xcodebuild test` with ad-hoc simulator signing. No Apple team.
5. Launches the app with `-WakeMeUpDemo` and saves screenshots (alarm list, editor, groups, sharing, ringing, and the list in Polish) as the `simulator-screenshots` artifact.

Screenshot launches do not ask for alarm permission and do not schedule with the system, so the dialog cannot cover the UI. The list is still the real SwiftUI screen, filled with demo data.

Regenerate the tones or the icon locally with Python 3:

```bash
python3 scripts/generate-sounds.py
python3 scripts/generate-icon.py
xcodegen generate   # once XcodeGen is installed
```

## What you need for the App Store

You can do all of this without a Mac. The macOS runner is the Mac.

### 1. Apple Developer Program

Enroll the Apple ID that will own the app at [developer.apple.com/programs](https://developer.apple.com/programs/). Approval is Apple's process, not something this repo can do. Budget the annual fee and a few days of waiting.

### 2. Bundle id

The project uses `com.grandelevas.wakemeup`. The widget is `com.grandelevas.wakemeup.widget`. Change both in `project.yml` if you want a different id, then keep these in lockstep:

| Place | Value |
| --- | --- |
| `project.yml` app target | `PRODUCT_BUNDLE_IDENTIFIER` |
| `project.yml` widget target | same id plus `.widget` |
| `Config/Release.entitlements` | `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)` and `group.$(PRODUCT_BUNDLE_IDENTIFIER)` expand from the bundle id |
| `WakeMeUp/WakeMeUpConfig.plist` | `iCloud.` plus the bundle id, for example `iCloud.com.grandelevas.wakemeup` |
| GitHub Actions variable `BUNDLE_ID` | optional, defaults to `com.grandelevas.wakemeup` |

Leave `CloudKitContainerID` **empty** until the container exists. An empty value keeps Sharing in on-device preview, including in TestFlight.

### 3. App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API.

Create a key with **Admin** or **App Manager** access. You need the certificate-creating role for the bootstrap lane.

GitHub repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID, 10 characters |
| `ASC_ISSUER_ID` | Issuer ID at the top of the keys page |
| `ASC_PRIVATE_KEY` | The entire `.p8` file, including `BEGIN PRIVATE KEY` |
| `APPLE_TEAM_ID` | Team ID from the distribution certificate. It is the OU on that certificate, the same 10 characters in parentheses after the name. Membership can list more than one team; this secret has to be the one that owns the certificate. The upload lane stops if they differ. |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | A password you invent. Set this **before** bootstrap. It encrypts the .p12 |
| `DISTRIBUTION_CERTIFICATE_P12_BASE64` | Added **after** bootstrap. Base64 of the .p12 from the artifact |

Optional repository variable `BUNDLE_ID` if you changed the bundle id.

Never commit the `.p8`, the `.p12`, or a provisioning profile. `.gitignore` already ignores them.

### 4. Portal records the API key cannot always finish

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources):

1. Register the app id `com.grandelevas.wakemeup` and the widget app id `com.grandelevas.wakemeup.widget`. The bootstrap lane does not create these. `produce` cannot authenticate with an API key in fastlane 2.242.
2. Create an iCloud container `iCloud.<bundle id>` and an App Group `group.<bundle id>`.
3. On the app id, enable Push Notifications, iCloud (CloudKit, that container), and App Groups (that group). The container and the group have to be checked on the app id, not only created.
4. On the widget id, no extra capability is required.

There is nothing to enable for AlarmKit. If a form or an old note mentions `com.apple.developer.alarmkit`, ignore it. That entitlement does not exist, and putting it in the file makes device signing fail.

The App Store Connect app record (the entry under Apps, not the App ID) is created by the bootstrap lane through the API. If the name WakeMeUp is already taken, the lane stops before creating a certificate and tells you to add the record yourself: Apps → + → New App, iOS, bundle ID `com.grandelevas.wakemeup`, SKU `wakemeup-ios`. Do not make an App Store record for the widget.

### 5. Bootstrap the certificate, then upload

Actions → **TestFlight** → Run workflow. Branch `main`. Action **bootstrap-signing** (not the default upload).

The lane checks the two bundle IDs, creates the App Store Connect app record if it is missing, and only then creates one Apple Distribution certificate. It wraps that key in `distribution.p12` using `DISTRIBUTION_CERTIFICATE_PASSWORD`. Profiles are created after the p12. If profiles fail, the workflow still uploads the `signing-bootstrap` artifact. Encode **distribution.p12** only. Do not run bootstrap again once that file exists.

1. After a successful bootstrap, download `signing-bootstrap`, base64-encode `distribution.p12`, and store it as `DISTRIBUTION_CERTIFICATE_P12_BASE64`. On iPhone, Shortcuts → Select File (the p12) → Base64 Encode (No Line Breaks, if shown) → Copy to Clipboard, then paste into the GitHub secret. Clear the clipboard afterward. Do not paste the file into chat.
2. Run the workflow again with **upload-testflight**. Fastlane imports the p12, downloads the profiles, archives Release, and uploads to TestFlight. The build will not appear for testers until App Store Connect finishes processing. The lane does not wait.
3. Later uploads can also be started by pushing a tag `v1.0.1`. Do not push a tag until the p12 secret exists. The workflow fails the preflight job with the name of each missing secret.

`fastlane/Fastfile` is the whole lane. It uses the App Store Connect API key with `cert`, `sigh`, and `upload_to_testflight`. It does not call `produce`. It does not use match and it does not need a second git repo.

Apple only allows a few distribution certificates per team. Do not run bootstrap twice. If the run fails before it says it created a certificate, it is safe to fix the cause and run bootstrap once more. If `distribution.p12` was uploaded, stop and store that secret instead.

### 6. App Store Connect metadata

- Name: WakeMeUp. Subtitle ideas: Remind me of / Przypomnij mi o.
- Primary category: Utilities or Health & Fitness.
- Privacy policy URL. Host `docs/privacy-policy.md`, replace the contact address, and paste the URL. A privacy policy is required.
- Age rating: no unrestricted web, no gambling, no user-generated public content. Song links open other apps.
- Export compliance: the app sets `ITSAppUsesNonExemptEncryption` to false (HTTPS only).
- Screenshots: App Store Connect wants device screenshots at the required sizes. The CI artifact is a Simulator capture for development, not a substitute for the 6.9-inch and 6.5-inch slots. TestFlight on a real iPhone is the right source. AlarmKit's full ring, especially through Silent, can only be confirmed on a device. The Simulator is enough to see the UI and to run the unit tests.
- Review notes: explain AlarmKit (alarms the person creates), the song link (opened only from a button), and remote alarms (invite and revoke, iCloud, both people opt in). Reviewers will ask what the alarm permission is for. The usage string is already specific.
- Privacy nutrition label: data is not collected by the developer. If you turn CloudKit on, say that alarm labels and song links are stored in the user's iCloud and are not shared with you. `PrivacyInfo.xcprivacy` declares no tracking and no collected data types.

### 7. Turn CloudKit on when you want real remote alarms

1. Finish step 4 so the container exists.
2. Set `CloudKitContainerID` in `WakeMeUp/WakeMeUpConfig.plist` to `iCloud.<bundle id>`.
3. Ship a TestFlight build (Release entitlements already request CloudKit, push, and the app group).
4. On a device signed into iCloud, open Sharing, create an invite, and send the link. The other phone pastes it and accepts.
5. In the CloudKit console, deploy the development schema to production before you ship to the App Store. TestFlight against the development environment works without that deploy. App Store builds do not.

## iOS behavior worth knowing

- Minimum system is **iOS 26.1**. AlarmKit arrived in iOS 26.0, and the alert API this app uses (a system Stop button plus one secondary button) is the iOS 26.1 form. Supporting iOS 18 would mean those phones can only use notifications, which do not ring through Silent. The notification path is still in the app, but only as the fallback when AlarmKit access is denied.
- A third-party app cannot become the system Clock and cannot start Spotify, YouTube, or Apple Music while the phone is locked unless the person taps a button. The button is the product.
- Custom alert sounds should stay at or under 30 seconds. Import enforces that. The bundled tones are about 12 seconds, 22.05 kHz, 16-bit mono WAV.
- Force-quitting WakeMeUp does not delete AlarmKit alarms that are already scheduled. It does stop the silent push that delivers a new remote alarm.
- Polish and English follow the iPhone language. Day letters follow the calendar's first weekday, so a Polish phone starts the week on Monday.

## Project layout

```
project.yml                 XcodeGen
WakeMeUp/                   app sources, strings, sounds, icon
WakeMeUpWidget/             Live Activity
WakeMeUpTests/              unit tests
Shared/                     alarm metadata
Config/Release.entitlements CloudKit, push, app group. Release only.
.github/workflows/ci.yml
.github/workflows/testflight.yml
fastlane/Fastfile
docs/privacy-policy.md
```
