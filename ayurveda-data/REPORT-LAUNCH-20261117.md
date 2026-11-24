# App Review launch and first-run appearance repair — 2026-11-17

Version: 1.1.2 (13), incremented from the rejected build 12 in both app and widget
configurations. Review reference: 8f62a2af-dd7a-4690-aad2-c18c9b2a4477.

## Confirmed cause and repair

The bundled catalogue carried 718,768 persistent-history changes. A main-thread
sample of the old build showed SwiftData/Core Data replaying catalogue history
during observation/profile persistence, leaving the visible app unresponsive for
minutes. A controlled simulator experiment removed only catalogue history and
made the same old binary responsive; the original history was restored before
the actual update test.

`CatalogStoreManager` now uses SwiftData's `deleteHistory` on the **staged
catalogue context only**, after validation/migration and before the read-only
mount. It verifies that no fetchable history remains. Installation format 2
forces older installations through this safe staged replacement even when the
content manifest has not changed. User-store records and user-store history are
not deleted; existing atomic publication and migration/recovery logic remain.
The replacement catalogue audit found zero ACHANGE rows and all 14,487 food
records retained. ATRANSACTION contained only a cleanup/metadata marker.

The launcher previously also waited for Calendar permission/recovery before
showing the app, with a competing permission request from bootstrap. It now
publishes readiness after local database work, then requests Calendar permission
and performs the existing automatic, tombstone-aware profile reconstruction.
Calendar requests share one in-flight task. Notification/Health permissions no
longer replace the root UI with a spinner. Calendar access is still required by
profile saving and calendar-backed features; declining it leaves onboarding
accessible and does not imply successful profile saving.

Both startup phases use `DatabaseLoadingView`, retaining the glass processing
card and adding the existing app logo above it. The screenshot preview argument
`-databaseLoadingPreview` is Debug-only and skips database work for a stable
capture; ordinary launches never take this branch.

First-run onboarding exposed a separate contrast issue: detached hosting-view
snapshots can be transparent before rendering, so their sampled darkness chose
white foreground over Morning Breath. `EffectManager` now resolves foreground
from the selected image or theme colors synchronously, including initialization,
launch, and later theme changes. Snapshots remain available for glass effects
but no longer determine text color. Loading uses the same foreground resolver.

## Validation

- Release simulator build of the database/permission repair succeeded. Its
  upgrade and calendar-restoration tests ran before the final loading-screen
  styling, automatic permission-prompt restoration, and contrast adjustment.
- Release update, without uninstalling, from build 12 with the original history:
  `testLaunchPreservesProfileAfterUpgrade` passed (21.218 s). All fields of the
  profile, three meals, and one training row exactly matched the pre-update
  snapshot, including the profile UUID.
- Reinstalled into an empty simulator app database while retaining EventKit
  data: `testLaunchRestoresProfileFromCalendar` passed (18.175 s). The test profile
  was reconstructed from its calendar metadata.
- Final launch-flow Debug build, fresh iPad Air 11-inch M3 simulator on iPadOS
  27.2: denied the Calendar prompt, typed a name, advanced onboarding, and
  relaunched successfully (42.427 s). No loading indicator remained.
- iPhone 16 Pro simulator on iOS 27.2: completed the entire profile wizard and
  saved its first profile successfully (55.196 s), with Calendar access granted.
- Signed Debug build installed as an update on the connected physical iPad Air
  11-inch M3, iPadOS 27.2. Launch probe reached its first interactive frame in
  5.041 s including catalogue replacement; calendar reconstruction completed
  after access was granted. Real-device app data was not reset or uninstalled.
- Existing launch/recovery source checks: 5/5 `test_database_launch_recovery.py`
  and 5/5 `test_we6_launch.py` pass. `git diff --check` passes.
- After the contrast fix, both final Debug builds succeeded. A second clean
  iPad installation with **dark system appearance** passed the denial,
  onboarding-interaction, and relaunch test (28.645 s). The light background's
  first profile screen was visually verified with black text and a light
  keyboard. Night Breath was also visually verified with white text and a dark
  keyboard while the system appearance was light. The updated build was
  installed again on the real iPad; launch
  and calendar reconstruction completed successfully (0.393 s to the first
  interactive frame with the prepared catalogue).

The broader `test_catalog_separation.py` has two pre-existing stale source-string
assertions (old relative-store URL syntax and a synchronous factory assignment)
against the prior async-bootstrap implementation; its other seven checks pass.
These failures are not runtime regressions introduced by this repair.

## Local evidence

- `/tmp/ayura-profile.sample.txt`: original main-thread history replay sample.
- `/tmp/ayura-upgrade-before.json`: full pre-update user-row snapshot.
- `/tmp/ayura-fixed-upgrade-ui.xcresult`: actual Release update test.
- `/tmp/ayura-calendar-restore-ui.xcresult`: empty-database calendar recovery.
- `/tmp/ayura-final-fresh-ui.xcresult`: first-run denial/onboarding/relaunch.
- `/tmp/ayura-final-iphone-profile-ui.xcresult`: first profile creation/save.
- `/tmp/ayura-device-launch.log`: physical-device launch and recovery markers.
- `/tmp/ayura-launch-fixed-final-build.log`: Release core repair build.
- `/tmp/ayura-theme-simulator-build.log`, `/tmp/ayura-theme-device-build.log`:
  final appearance-fix builds.
- `/tmp/ayura-theme-fresh-ui.xcresult`: final clean-install contrast/launch run.
- `/tmp/ayura-theme-device-launch.log`: final physical-device launch.

Screenshots are actual iPad simulator captures in
`/Users/aleksandarsvinarov/.codex/visualizations/2026/11/17/01a1e86c-4687-79e3-956f-300efdc088ec/`.

## App Store Connect upload and attachment

At the user's request, the complete final source (including the first-run
contrast fix) was archived in Release, exported with App Store distribution
profiles, and uploaded using the existing App Store Connect API key. The app and
widget both carry 1.1.2 (13); both profiles use team `8293TNMX6S`, have no device
list, and disable `get-task-allow`. The encryption declaration is false.

Apple upload processing completed with no errors or warnings. The build's API
processing state is `VALID`. A PATCH to the existing iOS version's build
relationship replaced build 12 with build 13; a subsequent GET confirmed the
saved relationship. On the user's subsequent submit instruction, the existing
rejected app-version item was marked resolved with build 13 attached, then the
existing submission was resubmitted through the API. The six subscription items
were retained. Both the version and submission now report `WAITING_FOR_REVIEW`;
the attached build was independently re-read and confirmed as 13. No separate
reviewer message was sent.

- App ID: `6800370073`
- App Store version ID: `5f1c7b4a-1cbf-4f89-9f07-b0b1f1fb8806`
- Build/delivery ID: `021eae27-960f-4531-91eb-c5877d15262d`
- Review submission ID: `8f62a2af-dd7a-4690-aad2-c18c9b2a4477`
- Resubmitted: `2026-11-17T08:58:56.989Z` (10:58 Europe/Sofia)
- IPA size: 1,023,082,858 bytes
- IPA SHA-256: `b84baea4eafc7416b3959f0f9f241295de8c35ff7593b921d6bea23af337b495`
- Archive, IPA, distribution settings, build/upload logs, source manifest, and
  API receipt: `/Users/aleksandarsvinarov/Desktop/AyurvedaAsanaYoga-release-2026-11-17/`
- App Store Connect: <https://appstoreconnect.apple.com/apps/6800370073/distribution/ios/version/inflight>
