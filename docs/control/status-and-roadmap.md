# HydraCam Status and Roadmap

Last control-plane migration: 2026-06-05.
Last status refresh: 2026-07-14.

This document is scoped to `/Users/jose/src/work/hydracamv2`, the Flutter mobile
repo. Backend, web, Azure, and AI/product work is recorded only when it blocks
or informs the mobile app.

## Current Mobile Status

2026-07-14 fleet Wi-Fi refresh: the five ADB-visible Android devices (Samsung
S9, S7 edge, and three S10e devices) now store both requested lab networks and
are connected to `Astral Express` on `192.168.178.0/24`. The local cleartext
credential JSON and Apple configuration profile are deliberately gitignored;
the evidence pack at
`logs/verification-runs/20260714-1407-astral-express-fleet-wifi/` records only
redacted commands and non-secret connection state. The iPhone 12 Pro and iPad
6th generation downloaded the Apple profile and still require confirmation of
the on-device Install approval. The POCO and iPhone 11 were not visible over
ADB, CoreDevice, or USB during this refresh, while the user's main S10e remained
intentionally out of scope.

2026-07-14 POCO install authorization update: the user recovered a Xiaomi
account, added a SIM, and enabled Install via USB on Xiaomi 2201116PG. Evidence
pack
`logs/verification-runs/20260714-1502-poco-x4-install-after-xiaomi-account/`
shows POCO `575ecf2cbd24` authorized over local ADB, current checkout
`8f1892d51805aed1c99138cbac58b77ff511bb11` building successfully, and debug
automation app `1.4.0+19` installing and launching as PID `5892`. MIUI required
one ten-second HydraCam confirmation; after selecting `Auswahl merken`, a
recorded follow-up `adb install -r` passed unattended. Screenshot, 8.69-second
video, package metadata, and startup logs prove the Master Control UI on real
hardware with no matched fatal/Flutter exception, ANR, or overflow marker. This
clears the former `INSTALL_FAILED_USER_RESTRICTED` blocker. Camera/session proof
remains pending because the POCO reports Wi-Fi `JuJo` at `192.168.0.9`, not the
fleet's last-proven `Astral Express` subnet `192.168.178.0/24`.

| Area | Status | Notes |
| --- | --- | --- |
| iOS simulator | Runs, but no camera | 2026-06-07 simulator run applied camera settings after camera/mic privacy grants, but Flutter `camera` reported no available cameras. Use simulator for launch/UI checks only, not capture proof. Latest parallel matrix kept it launch-only on bridge port `4771`. Evidence: `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md`. |
| iOS physical device | Recovered on current Profile automation builds; selected iPhone+iPad role switching passed | The prior broad white-screen blocker is superseded. `logs/verification-runs/2026-06-06-iphone-personal-team-debug/` shows iPhone 12 Pro debug launch, permissions, session creation, photo capture/upload, and video start. `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md` shows iPhone 12 Pro / iOS 26.5 passing the coordinated independent-capture matrix at `ultraWide` + `sport1080p60`, and iPad 5 passing `autoBack` + `standard1080p30`. `logs/verification-runs/20260608-auto-ios-host-warm-immediate-five-hot-rerun/` shows the no-tooling iPhone Profile bridge can be found by identity-based LAN scan without a manual `--ios-host`. Debug `Runner.app` still cannot be fast-launched by `devicectl` without Flutter tooling. After the iPad update to iOS 17.7.11, `logs/verification-runs/20260609-0021-ipad-physical-release-profile-smoke/` shows the connected iPad passing Profile build/install/launch through `devicectl`, warming an identity-matched bridge at `169.254.193.202:4762`, and passing one-device master photo/video capture. The Keepeyeonball follow-up `logs/verification-runs/20260609-0414-signing-jose-keepeyeonball-ios-redeploy-after-account/` confirms team `4RRY2QT7H8`, bundle `com.keepeyeonball`, and Apple ID `jose@keepeyeonball.com`: Profile build/install/launch succeeded on iPad and iPhone, iPhone `/healthz` passed at `192.168.178.168:4762` with target `00008101-000A68811E43001E`, and an iPhone automation screenshot was copied to `screenshots/iphone-keepeyeonball-standby.png`. In that same run the iPad app installed/launched but no bridge answered on `169.254.193.202`, `192.168.178.104`, `192.168.178.0/24`, or `169.254.193.0/24`. `logs/verification-runs/20260609-0557-ios-iphone-ipad-not-working/` reproduced the user report, removed the stale duplicate iPhone `com.vectorblanco.hydracam.dev` app, and showed the iPad was stalling after early bridge startup. Current recovery evidence `logs/verification-runs/20260609-0852-ios-iphone-ipad-recovery-continuation/` fixes the iPad startup stall by bounding startup permission requests to 8 seconds, keeps automation bridge bind failure non-fatal, rebuilds and installs patched Profile automation apps on both physical iOS devices, proves current standby screenshots for iPhone and iPad, restores both identity-matched bridges on standard port `4762`, and passes the selected physical iPhone+iPad immediate role-switch proof with explicit LAN hosts in `0.45s`. Use `--no-auto-ios-bridge-hosts` with explicit `--ios-host 00008101-000A68811E43001E=192.168.178.168` and `--ios-host 8b406aa5c597eab4c4dfd9908f4a09b10a89ec63=192.168.178.104` for this selected pair; otherwise identity auto-scan can adopt the iPhone link-local bridge and poison expected remote-client IP checks. Limitation: saved-video metadata remains unavailable on iOS multi-device matrices, though prior iPad evidence recorded native MP4 dimensions/fps in logs. |
| Android | In development; current role-switch evidence good; S7 camera path now preserves 1080p30 | 2026-06-07 parallel matrix: both Samsung S10e devices and Samsung SM-G960F captured one photo and one video at `standard1080p30` under a shared capture barrier. Current S7 edge code detects SM-G935F, preserves the requested capture profile, uses preset-default FPS, and retries timed-out still capture after controller reinitialization. `logs/verification-runs/20260609-1405-s7-higher-resolution-compat/` proves direct S7 automation-master `standard1080p30` JPEG and MP4 save with copied 1920x1080 artifacts. The standard backend-session matrix in the earlier `20260609-1012-s7-camera-compat-automation-exit` run still timed out on `start_session`; treat that as a session/backend automation issue, not a basic S7 camera-open failure. Xiaomi 2201116PG now passes current-build install, unattended update, launch, and UI smoke; camera/session proof remains pending after joining the fleet LAN. |
| Camera lens/profile settings | Implemented; device proof partial | 2026-06-07 added local lens preference and target video profiles from 480p30 through 4K60. The video profile selector now shows concrete target text (`1080p at 30 fps`, `1080p at 60 fps`) instead of arbitrary names; the latest parallel matrix confirms `/settings.videoCaptureTarget` on macOS, Android, iPhone, and iPad. iPhone 12 Pro 0.5x debug automation passes 1080p60 and 4K30 targets, but iOS metadata extraction is still unavailable. S7 now has current `standard1080p30` photo/video proof with 1920x1080 artifacts; S7 rear-wide 1080p60/4K30 remains intentionally unproven. ASAP item 0 remains open. |
| Camera setup and leveling | Implemented; physical proof partial | 2026-06-08 camera setup evidence shows local placement preview, warn-only red tilt guidance, perspective selector, and local capture-context metadata on reachable devices. Evidence roots: `logs/verification-runs/20260608-1435-camera-leveling-all-device-screenshots/`, `logs/verification-runs/20260608-1517-camera-leveling-remaining-device-gaps/`, and `logs/verification-runs/20260608-1533-camera-leveling-device-continuation/`. The latest S7 setup-preview rerun renders live camera video after rebooting the S7 to reset its stuck vendor camera service and using preset-default FPS for setup preview; the later `20260609-1405-s7-higher-resolution-compat` run proves direct S7 1080p photo/video save on the current compatibility path. The latest physical iPhone recovery attempt, `logs/verification-runs/20260608-1744-physical-iphone-resumed-recovery/`, briefly recovered the iPhone to CoreDevice `available (paired)` and Flutter wireless visibility, then launched the installed setup bridge, but that installed build was stale and lacked `capture_screenshot`; the current Profile build passed, but install attempts failed after the phone returned to CoreDevice unavailable / Flutter code -27. Physical iPhone setup screenshot/video proof remains blocked by device-side wireless developer availability, not app setup-preview code. |
| Mobile login/auth | Imperfect; development auto-login added for trusted dev builds | Current Auth0 login uses a browser-backed OAuth flow. Secure credential persistence, startup restore, refresh-token renewal, logout/end-session clearing, and HydraCam GUID restore now have local unit coverage, and desktop targets skip the mobile-only Auth0 restore/login path. Development builds can bypass the browser flow for attached automation devices with compile-time Dart defines: `HYDRACAM_DEV_AUTO_LOGIN=true`, `HYDRACAM_DEV_AUTO_LOGIN_EMAIL=<allowed-email>`, optional `HYDRACAM_DEV_AUTO_LOGIN_GUID=<guid>`, and optional `HYDRACAM_DEV_AUTO_LOGIN_PROFILE_PICTURE=<url>`. If no GUID define is supplied, the app resolves the user's HydraCam GUID by email before marking the session logged in. Keep this disabled in release lanes. Android emulator proof `logs/verification-runs/20260622-1925-android-emulator-dev-auto-login-smoke/` built with `HYDRACAM_DEV_AUTO_LOGIN_EMAIL=jose@keepeyeonball.com`, launched standby, captured an automation screenshot, and logged `Development auto-login restored user jose@keepeyeonball.com.` `scripts/run_hardware_ui_e2e.py` can now pass the same dev-login defines with `--dev-auto-login-email`, optional `--dev-auto-login-guid`, and optional `--dev-auto-login-profile-picture`. `docs/control/android-auth-sign-in-decision.md` keeps Auth0 Universal Login for the current release lane and defers Android Credential Manager / Sign in with Google until backend/Auth0 account linking is specified. Full Android/iOS auth smoke, Android process-death recovery, logout, and account-switch proof remain open. |
| Desktop and web | macOS controller debug path working; Win11 proof partial and aborted | macOS debug `.app` builds and launches for controller/monitoring use with a mock local camera. The 2026-06-09 Win11 triple-platform attempt proved native Windows real-webcam photo/video upload, proved WSL Linux and Android emulator only through fallback media, and did not complete the Windows/Linux/Android master-slave role matrix. Do not treat it as all-combinations desktop/emulator proof. Wrap-up: `docs/control/win11-triple-platform-proof-wrapup-2026-06-09.md`. The 2026-06-25/26 all-connected-device run proved fresh builds on all seven connected targets — macOS native (M1), Android emulator, iOS simulator, Chrome **web** (App 1.4.0+19, Slave Device screen, no console errors), and physical S10e + iPhone + iPad — each with a real screenshot/e2e at `logs/verification-runs/20260625-all-connected-device-matrix/`. A macOS-target build failure seen mid-run was a corrupt DerivedData/SPM cache, resolved by `flutter clean` + clearing `DerivedData/Runner-*` + rebuild (the macOS controller app runs natively on the M1 with a captured screenshot). |
| Wearable replay | Mock-first contract implemented; DAT entitlement passes; active phone/wearable pairing proven; physical streams still partial | `docs/control/wearable-replay-integration-plan.md` is the durable plan for Ray-Ban Meta POV plus Galaxy Watch4 telemetry. The current HydraCam slice adds wearable replay models, sidecar persistence, upload manifest shaping, Android/iOS mock native bridges, a Wear OS companion module, and focused Dart/Kotlin tests. The watch module requests sensor permissions, registers Wear OS Health Services `MeasureClient` heart-rate callbacks, merges standard accelerometer/gyroscope motion snapshots, and falls back to mock telemetry when unavailable. Because Meta DAT is unavailable in the mock lane, the emulator/simulator proof now requests and persists `rollingHighlight` POV fallback instead of continuous full-match DAT capture. Current packaged proof `logs/verification-runs/20260622-1831-wearable-replay-non-hardware-proof/summary.md` passed analyzer, readiness, serialized Flutter wearable tests, Android emulator native channel on `emulator-5554`, iOS simulator native channel on `6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3`, Wear OS module unit/build checks, media-timeline backend/frontend wearable tests, live HydraCam-generated manifest upload, and headless replay overlay verification. Android/iOS DAT registration metadata and callback schemes are pre-wired in developer mode without adding private SDK artifacts to default builds. `python3 scripts/check_wearable_replay_readiness.py mock` passes 56 checks, offline `python3 scripts/check_wearable_replay_readiness.py dat` passes the repo-controlled DAT registration/dependency-boundary checks, and the explicit external `GH_TOKEN="$(gh auth token)" python3 scripts/check_wearable_replay_readiness.py dat --check-network` package-access check now passes with `Android DAT GitHub Package access - HTTP 200`. media-timeline local proof accepts both synthetic bundles and a HydraCam-generated `wearable-upload-manifest.json`; current event `hydracam-wearable-live-1782146206076001` with POV id `b0db1ea1-d08b-4603-8509-63a606e6f3d1` renders the Ray-Ban POV replay/HR/motion/calibration/two-feedback-cue/audio/review status in the selected video playback overlay with no failed HTTP responses or browser console warning/error messages after label-store was started on `3004`. Physical hardware proof attempt `logs/verification-runs/20260622-1915-wearable-replay-real-device-clap-flash/summary.md` confirmed DAT entitlement and `:wearable:assembleDebug`, then blocked because no Android/Wear OS target was visible, no connected Ray-Ban Meta or Galaxy Watch4 appeared in host Bluetooth inventory, and physical iPhone/iPad were CoreDevice-unavailable / Flutter code `-27`. The 2026-06-23 rerun `logs/verification-runs/20260623-0335-wearable-replay-real-device-rerun/summary.md` found visible Android/iOS candidate devices, confirmed mock/offline/network DAT readiness, built `:wearable:assembleDebug` with JDK 17, and showed bonded Watch4/RB Meta entries on S10e `RF8M21J8XRT`, but Bluetooth state was disconnected. Latest partial hardware proof `logs/verification-runs/20260623-1518-wearable-replay-real-device-phone-connected/summary.md` proves active Bluetooth connections from `RF8M21J8XRT` to `Watch4 von Jose Ramon` and `RB Meta 00D5`, confirms `com.facebook.stella`, Samsung Watch Manager, Samsung Health Monitor, and HydraCam `1.4.0`/`versionCode=19`, and includes a real phone screenshot/video. Latest Watch4 proof `logs/verification-runs/20260623-1538-watch4-wearos-adb-hr-stream/summary.md` clears the Wear OS ADB gate: the Watch4 `SM-R875F` (API `36`) was paired/connected over wireless ADB at `192.168.178.117:41145`, the `:wearable` module installed on-device, and a real permission bug fixed (Health Services `MeasureClient` needs `android.permission.health.READ_HEART_RATE`, not just `BODY_SENSORS`, on Wear OS 5+); after declaring/granting that permission, HeartRate availability reads `ACQUIRING` with live motion samples and no registration failure. Remaining gates are real DAT SDK stream capture from Ray-Ban Meta, a wrist-worn Galaxy Watch4 non-zero heart-rate sample, and one full hardware clap/flash replay evidence pack. |
| Multi-device capture | Runtime role switching works; six-device iOS/Android current-build proof passed; fastest five-device hot loop remains separate | Master/slave WebSocket flow exists. `logs/verification-runs/20260607-runtime-role-switch-visible-physical-set/summary.json` proves Samsung G960F, Samsung S7 edge, Samsung S10e `RF8M90QE7LX`, physical iPad 5, and macOS can launch once, rotate which device is master, and connect the other four devices as slaves without relaunching. Current split-ack cold proof `logs/verification-runs/20260607-runtime-role-switch-async-ack-cold-four-local-fixed/summary.json` passed Samsung G960F, Samsung S7 edge, Samsung S10e `RF8M90QE7LX`, and macOS across two cycles / 8 rotations, but build/install/launch made it take `63.919s`. The fastest four-local proof is `logs/verification-runs/20260607-runtime-role-switch-slave-ack-poll25ms-staged-skew10-stress5-four-local/summary.json`: the same four targets passed explicit `--expect-target-id` selection across five hot cycles / 20 master rotations in `8.118s` runner elapsed, with no build/install/standby launch after warm preflight, `--stage-slaves-after-master-ready`, synchronous master acknowledgement, async accepted acknowledgement for slaves, 25 ms connected-client polling, and `--max-set-role-request-start-skew-ms 10` enforced. `logs/verification-runs/20260608-warm-summary-prime-five-repeat/summary.json` is the current fastest cold-iPhone repeat proof: using `--warm-summary` skipped `flutter devices`, `adb devices`, and master-host probing, launched only the missing iPhone Profile bridge, then passed Samsung G960F, Samsung S7 edge, Samsung S10e `RF8M90QE7LX`, iPhone 12 Pro `00008101-000A68811E43001E`, and macOS across five cycles / 25 rotations in `9.167s`. Parallel request-start skew stayed below `0.686 ms`, `set_role` averaged `162.803 ms`, and connected-client verification averaged `201.572 ms`. A separate pure-immediate warm-summary rerun, `logs/verification-runs/20260608-warm-summary-hot-five-repeat/summary.json`, passed the same 25 rotations in `8.806s` with no discovery, build, install, or launch; warm preflight had no missing bridges. Current physical iPhone+iPad recovery evidence `logs/verification-runs/20260609-0852-ios-iphone-ipad-recovery-continuation/device-logs/ios-two-device-immediate-role-switch-explicit-lan/summary.md` passed the selected pair across two master rotations in `0.45s` with both bridges on `4762` and explicit LAN hosts. Current six-device iOS/Android proof is recorded below. |
| Store distribution | Android signed AAB ready locally; current-source iOS App Store IPA export blocked by local signing; store upload credentials still unverified | Android recovery evidence `logs/verification-runs/20260609-0405-amaia23-android-developer-profile-recovery/summary.md` recreated an AMAIA23/HydraCam upload keystore and exported public certificate `android/amaia23-hydracam-upload-certificate-20260609.pem`; the current `1.4.0+18` Android release artifact built on 2026-06-21 with public store URL Dart defines is `build/app/outputs/bundle/release/app-release.aab` with SHA-256 `d570e6ebe507ad2a6f2de5c499cf5bd2cd2f162932bde63e47a728b51c75c8d9` and a matching store metadata sidecar. The Android release build no longer falls back to debug signing; the readiness preflight verifies preserved app IDs across platform manifests, Gradle, and fastlane, Android minSdk `24`, Android target/compile SDK at or above `35`, the Login screen privacy/support/account-deletion paths, `android/key.properties`, the referenced upload keystore, and the AAB signer SHA-256 fingerprint `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3` against the exported certificate. The current Android sidecar `build/app/outputs/bundle/release/app-release.aab.store-metadata.tsv` records the same artifact hash, builder, build override environment, and compiled store URL values; upload preflight now fails if an AAB/IPA sidecar is missing or mismatched. Launcher icons have been regenerated from `lib/assets/images/icon.png`; the readiness preflight now verifies referenced iOS app icons and Android launcher icon densities are real PNG assets. A prior default iOS IPA export produced SHA-256 `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`, but that IPA predates the bundled court-fallback and launcher-icon cleanups and has been removed from `build/ios/ipa/` so it cannot be mistaken for an upload candidate. The latest current-source iOS archive succeeded, then App Store IPA export failed with `No Accounts` and no `iOS Distribution` signing certificate; `security find-identity -v -p codesigning` shows Apple Development identities only. `ios/Runner/PrivacyInfo.xcprivacy` is bundled in the Runner app and `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption=false`; both are validated by `scripts/check_store_readiness.sh local`, which now fails truthfully on the missing local Distribution signing identity and warns that no current IPA exists plus missing external values. `scripts/check_store_readiness.sh upload` fails until a current IPA exists, upload credentials are provided, public non-placeholder HTTPS privacy/support/account-deletion URLs are configured, and artifact metadata sidecars match. `upload-ios` and `upload-android` now provide narrower TestFlight-only and Google-Play-only gates so one store credential does not block preflighting the other store; Android upload aliases now also cover `play-internal`, `play-closed`, and `play-production`. `scripts/google_play_release.sh` wraps the Android gate plus fastlane upload for `internal`, `closed_beta`, and `production_draft`; `scripts/google_play_internal_release.sh` remains a compatibility wrapper. Upload-certificate SHA-256 remains `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`. `vectorblanco@gmail.com` is signed into Chrome but lands on Play Console developer-account signup, so it has no visible existing Play developer profile there. `jose@keepeyeonball.com` is a recognized Google account and reaches the password challenge, but Play Console developer/app ownership remains unverified until that sign-in completes. Read-only Gmail and historical `HydraCam Dev Process` sheet checks found no Play Console ownership/invite/package-registration evidence. iOS targets Apple ID `jose@keepeyeonball.com`, team `4RRY2QT7H8`, and bundle `com.keepeyeonball`; `scripts/ios_fastlane.sh --version` now verifies the locked Homebrew Ruby/Bundler lane, and `scripts/android_fastlane.sh --version` verifies the locked Android fastlane lane. TestFlight upload remains blocked on local Distribution signing plus App Store Connect upload authentication: no local `APP_STORE_CONNECT_API_KEY_PATH`, no discovered `AuthKey_*.p8`, and no `FASTLANE_SESSION`. Google Play upload remains blocked on `GOOGLE_PLAY_JSON_KEY` and Play Console ownership. Real submission also depends on publishing the privacy/support/deletion drafts, privacy review, and release-lane device smoke tests. |

Latest media-timeline bridge unification work (2026-07-07):
The current stacked PR path moves HydraCam new-capture uploads toward
media-timeline without physically merging repositories. PR #7 adds bridge
request retry resilience, PR #8 carries media-timeline upload tokens as
runtime-only session state, and PR #9 adds the direct object-storage upload
sequence with a compatibility fallback. Follow-up PRs add
`scripts/check_media_timeline_bridge.py` and
`scripts/probe_media_timeline_direct_upload.py` so the bridge can be preflighted
and object-storage-probed before physical hardware runs. Local proof
`logs/verification-runs/20260707-141146-media-timeline-bridge-preflight-storage-enabled/`
shows backend health, media-storage readiness (`enabled: true`, provider `s3`,
bucket `media-timeline`), and the upload-start route mounted behind auth.
Local proof
`logs/verification-runs/20260707-141602-media-timeline-direct-upload-probe/`
then creates media-timeline event
`hydracam-8737f611-011f-4b3b-9e76-8b165dc023a5`, uploads one probe photo
through object storage, registers File Registry id
`b55694dc-dd18-45ed-b1fd-fa7d9d68c01f`, completes the bridge upload, and reads
session status with `photos: 1`, `total: 1`, `syncStatus: bridge-uploaded`.
The rotating master/slave matrix runner now accepts repeated `--dart-define`
flags and a safer `--media-timeline-bridge-api-base <url>` shortcut, passes the
resolved bridge defines through Android APK builds, iOS Profile builds, and
Flutter-run launches, and records only `dartDefineKeys` in matrix summaries.
Dry-run proof
`logs/verification-runs/20260707-rotating-matrix-media-timeline-bridge-flag-dry-run/`
shows the shortcut resolving `HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE` and
`HYDRACAM_MEDIA_TIMELINE_API_BASE_URL` without recording values. This is
backend/direct-object plus runner-readiness proof, not yet a physical HydraCam
device capture proof.

Latest all-connected-device deploy + smoke matrix (2026-06-25):
`logs/verification-runs/20260625-all-connected-device-matrix/` deployed and
smoke-tested the current `master-jose-2025` source on every connected target.
Branch state confirmed consolidated: `codex/hydracam-visual-makeover` was
identical to `master-jose-2025` and `codex/native-macos-camera-desktop` is fully
merged (all at `443a143b`); `flutter analyze` clean. Fresh-build PASSes with
dev-auto-login (`jose@keepeyeonball.com`): Android emulator `emulator-5554`
(API 34) passed `run_hardware_ui_e2e.py` setup+standby+scroll with no overflow
(APK exit 0); iOS Simulator iPhone 17 / iOS 26.5 launched to the Master Console
(WebSocket server on 4040, App 1.4.0+19, human-readable session name "Squash
match - 2026-06-25"); Chrome web (`flutter build web` exit 0, 15MB
`main.dart.js`) rendered the Slave Device screen with no console errors — a new
launch/UI render proof for the web target. A 2026-06-26 round-2 pass then
cleared every remaining target, so all SEVEN connected targets build, deploy,
and render the current source with fresh builds and real screenshots: macOS
native (M1, bridge `127.0.0.1:4762`), Android emulator, iOS Simulator, Chrome
web, physical Samsung S10e (SM-G970F, `RF8M21J8XRT`), physical iPhone 12 Pro
(`00008101-000A68811E43001E`, bridge `192.168.178.170:4762`), and physical
iPad 5 (`8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, bridge
`192.168.178.104:4762`). Resolution notes: the recurring **macOS** build failure
("Build operation failed without specifying any errors", reaching CopySwiftLibs)
was a corrupt DerivedData/SPM cache — fixed by `flutter clean` + `rm -rf
~/Library/Developer/Xcode/DerivedData/Runner-*` + rebuild; the **physical iOS**
devices only needed unlock/wake (the previously-installed iPhone build lacked
automation, so a fresh `flutter build ios --profile
--dart-define=HYDRACAM_AUTOMATION=true` build was installed via `devicectl`,
launched standby, and its bridge found by identity-matched LAN scan at the live
IP `.170` rather than the stale cached `.168`); the **S10e** screenshot only
needed the dozing screen woken (`input keyevent KEYCODE_WAKEUP` + `svc power
stayon true`). The iOS-device build toolchain works; the macOS-only failure was
build-cache corruption, not a HydraCam defect. See the run's `summary.md` and
`device-logs/`.

Latest all-hardware iOS/Android update proof:
`logs/verification-runs/20260609-0930-all-hardware-ios-android-update-role-test/`
built the current automation-enabled Android APK (`1.4.0+16`, minSdk 24),
installed it on Samsung G960F `29d816ac550b7ece`, Samsung S7 edge
`9885e6503930304946`, Samsung S10e `RF8M21J8XRT`, and Samsung S10e
`RF8M90QE7LX`, and confirmed all five visible Android phones were on
`192.168.178.0/24`. Xiaomi 2201116PG `575ecf2cbd24` remained blocked by
device-side `INSTALL_FAILED_USER_RESTRICTED`, so it was recorded as excluded
from the current-build role proof. The current-build role-switch run
`device-logs/six-device-current-build-role-switch/summary.md` passed six
rotations in `43.435s` across the four updated Androids plus physical iPhone
12 Pro `00008101-000A68811E43001E` and iPad 5
`8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`; every selected device became
master once and saw the other five connected clients. The evidence pack also
contains six screenshots and one Android foreground screen recording.

Latest S7 camera compatibility proof:
`logs/verification-runs/20260609-1405-s7-higher-resolution-compat/`
verifies the corrected Samsung S7 edge / SM-G935F compatibility path on the
physical S7 (`9885e6503930304946`, Android 8/API 26). Device logs show the
policy preserving requested `standard1080p30`, using platform-default FPS, then
saving `session_null/CAP3852750848982854487.jpg` and
`session_null/REC5731514365530415283.mp4`. Copied artifacts
`screenshots/s7-standard1080p30-photo.jpg` and
`video/s7-standard1080p30-video.mp4` are readable; the JPEG EXIF reports
`SM-G935F` at 1920x1080, `ffprobe` reports the MP4 stream at 1920x1080, and app
video metadata reports `1920x1080, unknown fps, 13962 ms`. The earlier
`logs/verification-runs/20260609-1012-s7-camera-compat-automation-exit/`
720x480 workaround is superseded for S7 camera resolution, but still records
the automation standby escape fix. The standard single-device backend-session
matrix in that earlier run still timed out on `start_session`, so S7 camera
compatibility should be tracked separately from backend/session automation
health.

Latest acceleration proof: `logs/verification-runs/20260608-latest-cache-shortest-default-staged-five-hot/summary.json`
passed Samsung G960F, Samsung S7 edge, Samsung S10e `RF8M90QE7LX`, iPhone 12
Pro `00008101-000A68811E43001E`, and macOS across five cycles / 25 master
rotations in `7.844s` using the automatically persisted latest warm-summary
cache, no manual `--warm-summary`, no target list, no explicit
`--stage-slaves-after-master-ready`, no missing warm bridges, and max parallel
slave request-start skew `1.349 ms`. The runner now makes the staged-master /
parallel-slaves path the default for immediate hot runs. A fully parallel
diagnostic probe,
`logs/verification-runs/20260608-latest-cache-short-command-five-hot-fully-parallel-probe/summary.json`,
also passed but took `22.344s` because slave registration lag rose sharply when
clients raced the promoted master's WebSocket server startup.

Role-switch runner setup hardening:
`logs/verification-runs/20260618-1846-android-adb-setup-timeouts/` adds focused
regression coverage for Android `prepare_android_target()`: `adb install` is
bounded at 120 seconds, `adb forward` is bounded by the 8 second setup budget,
and either timeout now raises `MatrixRunError` with the target device id instead
of leaving the matrix waiting indefinitely. This is script-level proof only;
rerun the live hardware matrix before using it as fresh device evidence.

## Latest One-by-One Device Rerun

Evidence root: `logs/verification-runs/20260607-all-devices-one-by-one-rerun/`.

2026-06-07 current results:

- macOS passed the mock/controller capture repro at `autoBack` +
  `standard1080p30`.
- iOS simulator launched and started the automation bridge, but Flutter reported
  no available cameras; keep it as launch/UI evidence only.
- Physical iPad passed on a clean bridge-discovery run with `autoBack` +
  `standard1080p30`, one photo, one video, and recording false after stop.
  Saved-video metadata remains unavailable.
- At that time, iPhone 12 Pro was blocked: clean bridge-discovery run built and
  entered Xcode install/launch but no automation bridge appeared; direct
  `devicectl` launch was denied because the phone was locked.
- Samsung S10e passed `autoBack` + `standard1080p30`, including inactive session
  completion.
- Samsung S7 edge failed the baseline `compat720p30` capture before photo save;
  logcat shows repeated `ExynosCamera3` wait timeouts.
- Xiaomi 2201116PG remains blocked before app launch by
  `INSTALL_FAILED_USER_RESTRICTED`.

The first iPad/iPhone auto-discovery attempts in that evidence root are marked
invalid because they discovered the S10e bridge. Use the `clean-bridge` iPad and
iPhone directories for current iOS evidence.

Follow-up blocker rerun:
`logs/verification-runs/20260607-remaining-blockers-rerun/summary.md` records
fresh checks for the three still-unverified devices. Samsung S7 edge still
fails before photo save even at `dataSaver480p30`; at that time iPhone 12 Pro
direct launch was denied because the phone was locked; Xiaomi still fails debug
APK install with `INSTALL_FAILED_USER_RESTRICTED`. The later new-devices rerun
below supersedes the iPhone lock blocker for debug automation capture, and the
later `20260609-1405-s7-higher-resolution-compat` run supersedes this S7 camera
failure with direct 1920x1080 photo/video proof.

## Latest New-Devices Rerun

Evidence root: `logs/verification-runs/20260607-new-devices-rerun/`.

2026-06-07 fresh-device results:

- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60` debug
  automation capture: one photo, one video, recording stopped, bridge
  `http://192.168.178.141:4762`, iOS-native trace path under `/var/mobile/`.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `detail4k30` debug automation
  capture with the same selected 0.5x camera id. Saved-video metadata was still
  unavailable for both iPhone runs.
- New Samsung SM-G970F / Android 12 (`RF8M21J8XRT`) passed `autoBack` +
  `standard1080p30`, captured one photo and one video, ended the session, and
  logged recorded video metadata as `1920x1080, unknown fps, 3966 ms`.
- New Samsung SM-G960F / Android 10 (`29d816ac550b7ece`) failed before photo
  save at both `standard1080p30` and `compat720p30`; logs show CameraX
  `ImageCaptureException: Not bound to a valid Camera` after camera `0`
  initialization.
- Samsung S7 edge / Android 8 (`9885e6503930304946`) still failed before photo
  save even at `dataSaver480p30`; app logs show a 12 second photo timeout and
  logcat shows ExynosCamera3 wait timeouts plus Camera2 reopen / max-camera
  errors.

## Latest Post-Label Device Matrix

Evidence root: `logs/verification-runs/20260607-post-label-device-matrix/`.

This run verifies the device matrix after replacing video-profile display names
with concrete target labels.

- macOS passed `autoBack` + `standard1080p30`; `/settings` reported
  `videoCaptureTarget: 1080p at 30 fps`.
- Samsung S10e devices `RF8M90QE7LX` and `RF8M21J8XRT` passed `autoBack` +
  `standard1080p30`, ended their automation sessions, and logged
  `1920x1080, unknown fps` metadata.
- Samsung SM-G960F / Android 10 (`29d816ac550b7ece`) passed `autoBack` +
  `standard1080p30` on the current APK, with `1920x1080, unknown fps` metadata.
  This supersedes the earlier G960F failure in the new-devices rerun.
- Samsung S7 edge / Android 8 (`9885e6503930304946`) still failed before photo
  save at `standard1080p30`; app logs show a 12 second timeout and logcat shows
  ExynosCamera3 / Camera2 reopen errors.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60`; `/settings`
  reported `videoCaptureTarget: 1080p at 60 fps`. Saved-video metadata remained
  unavailable.
- Physical iPad / iOS 15.6.1 passed `autoBack` + `standard1080p30` only in the
  explicit-host run at `192.168.178.104`; auto-discovered iPad artifacts in
  this root are invalid because they attached to the iPhone bridge. Saved-video
  metadata remained unavailable.
- iOS simulator launched and exposed the automation bridge, but it remains
  launch/UI-only because Flutter reported no cameras available.

## Latest Parallel Device Matrix

Evidence root:
`logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/`.

This run validates independent local capture on all connected targets through a
shared capture barrier. It intentionally launched each capture-capable device as
a local master to prove lens/profile/capture settings per device; it is not a
master/slave discovery or synchronized broadcast proof.

- Shared barrier released at `2026-06-07T16:06:09.664388`.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60`;
  `/settings` reported `videoCaptureTarget: 1080p at 60 fps`.
- iPad 5 / iOS 15.6.1 passed `autoBack` + `standard1080p30` through explicit
  host `192.168.178.104`.
- Follow-up evidence in
  `logs/verification-runs/20260607-1708-ipad-network-identity-check/` fixed
  iPad IP reporting: the screen previously rendered USB/link-local
  `169.254.9.236`, while the real bridge host was `192.168.178.104`; the
  updated route-ranked IP selection now renders `192.168.178.104`.
- macOS passed `autoBack` + `standard1080p30` on unique automation port `4770`.
- Samsung SM-G960F and both S10e devices passed `autoBack` +
  `standard1080p30`.
- Samsung S7 edge still failed before photo save and was classified from
  collected logcat as `s7_exynos_camera_timeout`; this S7 result is superseded
  for camera resolution by the later
  `20260609-1405-s7-higher-resolution-compat` 1920x1080 proof.
- iOS simulator launched with automation port `4771`, but remains launch-only
  because no camera is exposed.

## Latest Runtime Role-Switch Matrix

Evidence roots:

- `logs/verification-runs/20260607-runtime-role-switch-local-smoke-timed/`
- `logs/verification-runs/20260607-runtime-role-switch-ipad-macos-currentbuild/`
- `logs/verification-runs/20260607-runtime-role-switch-ipad-macos-reuse/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-skipinstall/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-currentapk-expected-ip/`
- `logs/verification-runs/20260607-runtime-role-switch-ipad-android-macos/`
- `logs/verification-runs/20260607-runtime-role-switch-visible-physical-set/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-prime-direct-macos/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-immediate-second/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-no-success-logs/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-summary-fastpath/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-summary-subsecond-poll/`
- `logs/verification-runs/20260607-runtime-role-switch-warm-summary-no-adb-forward/`
- `logs/verification-runs/20260607-runtime-role-switch-mobile-warm-summary-fastpath/`
- `logs/verification-runs/20260607-runtime-role-switch-android-current-cache-proof/`
- `logs/verification-runs/20260607-runtime-role-switch-android-current-cache-warm-rerun/`
- `logs/verification-runs/20260607-runtime-role-switch-mobile-current-cache-warm-fastpath/`
- `logs/verification-runs/20260607-runtime-role-switch-android-handler-race-fix/`
- `logs/verification-runs/20260607-runtime-role-switch-android-handler-race-fix-warm-prime/`
- `logs/verification-runs/20260607-runtime-role-switch-android-handler-race-fix-warm-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-android-single-master-g960f-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-android-health-identity-proof/`
- `logs/verification-runs/20260607-runtime-role-switch-android-health-identity-warm-prime/`
- `logs/verification-runs/20260607-runtime-role-switch-android-health-identity-warm-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-android-health-identity-single-g960f/`
- `logs/verification-runs/20260607-macos-standby-persistence-experiment/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-shared-bind-current/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-shared-bind-warm-prime/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-detached-warm-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-detached-warm-immediate-repeat/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-detached-runner-warm-prime/`
- `logs/verification-runs/20260607-runtime-role-switch-android-macos-detached-runner-warm-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-four-local-adopted-warm-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-visible-set-adopted-fast-ipad-timeout/`
- `logs/verification-runs/20260607-runtime-role-switch-visible-set-warm-only-fast-fail/`
- `logs/verification-runs/20260607-runtime-role-switch-four-local-warm-only-immediate/`
- `logs/verification-runs/20260607-runtime-role-switch-immediate-flag-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-immediate-flag-visible-fast-fail/`
- `logs/verification-runs/20260607-runtime-role-switch-immediate-flag-parallel-timings-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-immediate-flag-parallel-timings-visible-fast-fail/`
- `logs/verification-runs/20260607-runtime-role-switch-ipad-warm-prime-only-current/`
- `logs/verification-runs/20260607-runtime-role-switch-visible-warm-prime-only-current/`
- `logs/verification-runs/20260607-runtime-role-switch-immediate-after-warm-prime-change-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-prime-then-immediate-visible-current/`
- `logs/verification-runs/20260607-runtime-role-switch-prime-then-immediate-four-local-current/`
- `logs/verification-runs/20260607-runtime-role-switch-prime-then-immediate-visible-action-current/`
- `logs/verification-runs/20260607-runtime-role-switch-prime-then-immediate-action-four-local-current/`
- `logs/verification-runs/20260607-runtime-role-switch-expected-iphone-guard-current/`
- `logs/verification-runs/20260607-runtime-role-switch-expected-visible-five-current/`
- `logs/verification-runs/20260607-runtime-role-switch-expected-four-local-current/`
- `logs/verification-runs/20260607-runtime-role-switch-phase-baseline-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-master-command-poll-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-phase-timings-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-slave-registration-cold-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-direct-macos-warm-prime-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-slave-registration-warm-immediate-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-slave-registration-warm-immediate-repeat-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-forced-slave-connect-cold-four-local-rerun/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-forced-slave-connect-warm-prime-chainable-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-forced-slave-connect-warm-immediate-repeat-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-master-client-registration-cold-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-fast-master-client-registration-warm-immediate-repeat-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-zero-route-stale-slave-cold-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-zero-route-stale-slave-warm-prime-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-zero-route-stale-slave-warm-immediate-repeat-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-zero-route-stale-slave-warm-immediate-repeat2-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-zero-route-stale-slave-warm-immediate-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-registration-lag-instrumented-cold2-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-registration-lag-instrumented-warm-prime-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-registration-lag-instrumented-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-current-code-cold-parallel-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-current-code-warm-prime-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-current-code-parallel-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-current-code-staged-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-async-ack-cold-four-local-fixed/`
- `logs/verification-runs/20260607-runtime-role-switch-async-ack-warm-prime-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-async-ack-staged-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-slave-ack-staged-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-slave-ack-poll25ms-staged-skew10-stress5-four-local/`
- `logs/verification-runs/20260607-runtime-role-switch-visible-physical-warm-prime-after-iphone-visible/`
- `logs/verification-runs/20260607-runtime-role-switch-iphone-fast-warm-prime-after-visible/`
- `logs/verification-runs/20260607-ipad-xctrace-launch-live-poll/`
- `logs/verification-runs/20260607-ipad-explicit-automation-ipa-xctrace/`
- `logs/verification-runs/20260607-runtime-role-switch-ipad-xctrace-trust-fail/`
- `logs/verification-runs/20260607-runtime-role-switch-iphone-console-launch/`
- `logs/verification-runs/20260607-runtime-role-switch-iphone-current-profile-install-fast-launch-scan/`
- `logs/verification-runs/20260607-runtime-role-switch-iphone-profile-launch-config-retry-scan/`
- `logs/verification-runs/20260607-runtime-role-switch-iphone-engine-registrar-profile-scan/`
- `logs/verification-runs/20260607-runtime-role-switch-five-with-iphone-profile-hot/`
- `logs/verification-runs/20260608-auto-ios-host-fast-launch-five-hot/`
- `logs/verification-runs/20260608-auto-ios-host-warm-immediate-five-hot-rerun/`
- `logs/verification-runs/20260608-ipad-xctrace-trust-rerun/`
- `logs/verification-runs/20260608-all-selected-auto-iphone-ipad-xctrace-rerun/`
- `logs/verification-runs/20260608-ipad-profile-install-fallback-warm-prime/`
- `logs/verification-runs/20260608-current-hot-five-after-ios-install-fallback/`
- `logs/verification-runs/20260608-all-selected-trust-retry-short/`
- `logs/verification-runs/20260608-prime-five-after-trust-retry-code/`
- `logs/verification-runs/20260608-hot-five-after-trust-retry-code-rerun/`
- `logs/verification-runs/20260608-prime-five-stress5-after-trust-retry-code/`
- `logs/verification-runs/20260608-hot-five-after-stress5-immediate/`
- `logs/verification-runs/20260608-warm-summary-prime-five-repeat/`
- `logs/verification-runs/20260608-warm-summary-hot-five-repeat/`
- `logs/verification-runs/20260608-latest-cache-seed-five-hot/`
- `logs/verification-runs/20260608-latest-cache-auto-five-hot/`
- `logs/verification-runs/20260608-latest-cache-reseed-five-hot-after-cache-fix/`
- `logs/verification-runs/20260608-latest-cache-short-command-five-hot-after-cache-fix/`
- `logs/verification-runs/20260608-latest-cache-short-command-five-hot-fully-parallel-probe/`
- `logs/verification-runs/20260608-latest-cache-shortest-default-staged-five-hot/`
- `logs/verification-runs/20260608-ipad-warm-prime-after-default-staged-with-host/`

Current runtime-switch result:

- macOS + iOS simulator launched once in standby, switched macOS to master and
  simulator to slave in `119.533 ms`, and confirmed one connected slave. This
  remains launch/UI proof only because the simulator has no camera.
- Physical iPad 5 + macOS passed both master rotations on the current build.
  iPad-as-master switched both targets in `181.19 ms` and saw macOS as one
  connected slave from `192.168.178.159`; macOS-as-master switched both targets
  in `143.527 ms` and saw iPad as one connected slave from `192.168.178.104`.
- Samsung S10e `RF8M90QE7LX` + macOS passed after building/installing a current
  automation APK using local NDK override `27.0.12077973`. The stricter rerun
  `20260607-runtime-role-switch-android-macos-currentapk-expected-ip` validates
  expected client remote IPs so an unrelated iPad connection cannot satisfy the
  proof. Android-as-master switched both targets in `517.921 ms`; macOS-as-master
  switched both targets in `224.823 ms`.
- Samsung S10e `RF8M90QE7LX` + physical iPad 5 + macOS passed all three master
  rotations in `20260607-runtime-role-switch-ipad-android-macos`. Android,
  iPad, and macOS each became master once; the other two devices connected as
  slaves with expected remote IPs. Parallel `set_role` elapsed times were
  `530.195 ms`, `188.846 ms`, and `155.552 ms`.
- The visible physical set passed in
  `20260607-runtime-role-switch-visible-physical-set`: Samsung G960F
  `29d816ac550b7ece`, Samsung S7 edge `9885e6503930304946`, Samsung S10e
  `RF8M90QE7LX`, physical iPad 5, and macOS each became master once. Every
  rotation saw four expected slave remote IPs. Parallel `set_role` elapsed times
  were `878.015 ms`, `503.621 ms`, `308.356 ms`, `234.084 ms`, and `223.33 ms`.
- Warm reuse acceleration now avoids the slowest repeat-run costs for role-only
  matrices. The runner preserves Android ADB forwards in reuse mode, skips
  Android permission grants when an existing bridge exposes `set_role`, launches
  macOS standby from the already-built debug app instead of `flutter run`, and
  skips per-device logcat/log collection on successful role-only rotations
  unless `--collect-role-switch-logs` is requested. The latest timed run
  `20260607-runtime-role-switch-warm-no-success-logs` passed four master
  rotations in `15.31s` wall time; the individual runtime `set_role` calls were
  `120.19 ms`, `149.504 ms`, `156.199 ms`, and `120.034 ms`.
- Warm-summary acceleration removes the remaining repeat discovery path by
  loading targets and master hosts from a previous summary instead of calling
  `flutter devices`, `adb devices`, and Android Wi-Fi host probes. With
  subsecond connected-client polling and no unnecessary Android forward refresh,
  `20260607-runtime-role-switch-warm-summary-no-adb-forward` passed four master
  rotations in `4.34s` wall time; `set_role` calls were `164.229 ms`,
  `128.043 ms`, `180.563 ms`, and `101.627 ms`. The mobile-only warm-summary
  run `20260607-runtime-role-switch-mobile-warm-summary-fastpath` passed
  Samsung G960F, Samsung S10e `RF8M90QE7LX`, and physical iPad as master in
  `2.59s` wall time; `set_role` calls were `122.068 ms`, `136.183 ms`, and
  `116.361 ms`, and every rotation saw the expected slave remote IPs. Use
  `--warm-summary` only with a current warm bridge map; stale summaries can
  intentionally fail if ports now point at different devices.
- App-side master registration now caches the master network snapshot for a
  short registration burst, avoiding duplicate platform/network probes while
  several slaves reconnect to a newly promoted master. After rebuilding and
  reinstalling the current Android APK with the local NDK override, the warm
  Android-only rerun `20260607-runtime-role-switch-android-current-cache-warm-rerun`
  passed both Android master rotations in `1.54s` wall time (`263.432 ms` and
  `119.812 ms` `set_role` calls). The current mobile warm run
  `20260607-runtime-role-switch-mobile-current-cache-warm-fastpath` passed
  Samsung G960F, Samsung S10e `RF8M90QE7LX`, and physical iPad as master in
  `2.06s` wall time with expected slave remote IPs; `set_role` calls were
  `221.557 ms`, `167.678 ms`, and `141.746 ms`.
- Runtime automation handler cleanup is now identity-safe, so an old
  `MasterScreen` dispose cannot unregister commands from a newer promoted
  `MasterScreen` during rapid route replacement. The failing symptom was a warm
  bridge that still exposed `set_role` but lost `connected_clients`, causing a
  role-only proof to wait for the timeout and fail. After the fix, the cold
  Android proof `20260607-runtime-role-switch-android-handler-race-fix` passed
  two Android master rotations after a `22.5s` debug APK build; the first fresh
  post-install switch took `3721.383 ms`, while the second took `296.065 ms`.
  The warm prime run took `10.13s` wall time with app launch/permission setup;
  the warm immediate rerun took `1.50s` wall time for both Android master
  rotations, with `set_role` calls of `241.26 ms` and `182.072 ms`. The
  single-master immediate proof
  `20260607-runtime-role-switch-android-single-master-g960f-immediate` completed
  in `0.64s` wall time with a `233.4 ms` `set_role` call. These Android-only
  filtered runs also saw an already-running iPad as an extra slave IP; they
  prove expected-client presence, not isolation from unselected LAN devices.
- Android automation setup now grants only manifest/API-appropriate runtime
  permissions, avoiding repeated `pm grant` failures for storage/media
  permissions that are not declared on newer API levels. This reduces setup
  noise and removes avoidable ADB commands from non-warm runs.
- Automation `/healthz` now reports `automationTargetId`, and warm bridge reuse
  requires that value to match the selected runner target before setup is
  skipped. Launch paths stamp this identity through Android intent extras,
  Flutter dart defines, physical iOS/macOS environment variables, and direct
  macOS debug-app environment variables. The cold Android identity proof
  `20260607-runtime-role-switch-android-health-identity-proof` passed both
  Android master rotations after a `32.5s` debug APK build, with `set_role`
  calls of `886.204 ms` and `314.953 ms`. The warm-prime run showed
  `/healthz` target identity on both ports and passed in `9.87s` with app
  launch/setup. The identity-gated warm-immediate run
  `20260607-runtime-role-switch-android-health-identity-warm-immediate` skipped
  ADB setup entirely and passed both Android master rotations in `1.42s` wall
  time, with `set_role` calls of `267.148 ms` and `161.244 ms`. The single
  promoted-master proof
  `20260607-runtime-role-switch-android-health-identity-single-g960f` completed
  in `0.93s` wall time with a `210.256 ms` `set_role` call.
- Warm bridge reuse now adopts already-running local ports by
  `automationTargetId` instead of trusting stale static port order. This keeps a
  subset run from forcing relaunch when the next run adds S7 or macOS back into
  the matrix. After reinstalling the current debug APK on S7, the adopted
  four-local warm run
  `20260607-runtime-role-switch-four-local-adopted-warm-immediate` passed G960F,
  S7, S10e `RF8M90QE7LX`, and macOS as master in `4.50s` wall time.
- For true immediate runs, use `--require-warm-bridges` with
  `--reuse-running-bridges`. That mode does not build, install, or launch; it
  fails before setup if any selected bridge is missing or stale. The all-visible
  warm-only preflight
  `20260607-runtime-role-switch-visible-set-warm-only-fast-fail` failed in
  `0.81s` and wrote `warm-bridge-preflight.json` naming the missing physical
  iPad bridge at `http://192.168.178.104:4762`. The four-local warm-only proof
  `20260607-runtime-role-switch-four-local-warm-only-immediate` then passed all
  four master rotations in `3.42s` wall time; `set_role` calls were
  `244.483 ms`, `208.747 ms`, `161.403 ms`, and `223.04 ms`.
  `--immediate-role-switch` now wraps the same fast recipe: runtime role
  switching, role-switch-only verification, bridge reuse, required warm bridge
  preflight, skip build, and skip install. Use it with a current
  `--warm-summary` and selected `--target-id` filters for the lowest-latency
  loop; a cold or stale selected device writes `warm-bridge-preflight.json` and
  exits before expensive work.
  `20260607-runtime-role-switch-immediate-flag-four-local` verifies the one-flag
  path on G960F, S7 edge, S10e `RF8M90QE7LX`, and macOS in `3.85s` wall time
  with `set_role` calls of `191.316 ms`, `163.988 ms`, `148.818 ms`, and
  `133.595 ms`. The all-visible one-flag preflight
  `20260607-runtime-role-switch-immediate-flag-visible-fast-fail` fails in
  `0.74s` and names only the missing iPad bridge; no build, install, or launch
  is attempted.
  `20260607-runtime-role-switch-immediate-flag-parallel-timings-four-local`
  adds per-target request timing evidence and passed the same four warm local
  targets in `3.68s` wall time. `set_role` elapsed times were `141.074 ms`,
  `149.802 ms`, `544.174 ms`, and `185.929 ms`; request start skew was
  `0.332 ms`, `0.555 ms`, `0.836 ms`, and `0.892 ms`, proving the role-change
  POSTs are dispatched in parallel even when one device responds slower.
  The current-code all-visible preflight
  `20260607-runtime-role-switch-immediate-flag-parallel-timings-visible-fast-fail`
  fails in `0.86s` with only the missing iPad bridge in
  `warm-bridge-preflight.json`; no rotation summary is written because no
  build, install, or launch is attempted.
  `--warm-prime-only` is the companion setup command: it reuses existing warm
  bridges, skips build/install, tries to launch only missing selected bridges,
  writes `warm-bridge-prime.json`, and exits without running rotations. The
  then-current all-visible warm-prime run
  `20260607-runtime-role-switch-visible-warm-prime-only-current` attempted only
  the missing iPad bridge and failed in `3.91s` with
  `ios_profile_not_trusted`; Android and macOS bridges remained warm. The
  then-current post-change immediate proof
  `20260607-runtime-role-switch-immediate-after-warm-prime-change-four-local`
  passed G960F, S7 edge, S10e `RF8M90QE7LX`, and macOS in `3.97s` wall time
  with request start skew below `1 ms` on every rotation.
  `--prime-then-immediate-role-switch` is now the preferred single command for
  the final fast loop: it writes `warm-bridge-prime.json`, stops immediately if
  any selected bridge remains cold, and otherwise continues into the required
  warm preflight plus immediate role-switch proof. The all-visible then-current
  run
  `20260607-runtime-role-switch-prime-then-immediate-visible-current` stopped in
  `3.86s` after the iPad xctrace launch reported `ios_profile_not_trusted`; no
  `warm-bridge-preflight.json` or rotation artifacts were written. The warm
  four-device run
  `20260607-runtime-role-switch-prime-then-immediate-four-local-current` passed
  in `3.79s`; `warm-bridge-prime.json` and `warm-bridge-preflight.json` both
  passed, `set_role` calls were `138.101 ms`, `183.703 ms`, `124.045 ms`, and
  `160.24 ms`, and request start skew stayed at about `1.2 ms` or less.
  The action-enhanced rerun
  `20260607-runtime-role-switch-prime-then-immediate-visible-action-current`
  fails in `4.28s` and adds `deviceActions[0].code=ios_profile_not_trusted`
  with the exact iPad trust step: Settings > General > VPN & Device Management.
  The matching warm-four proof
  `20260607-runtime-role-switch-prime-then-immediate-action-four-local-current`
  passes in `3.75s`; `set_role` calls were `187.26 ms`, `221.56 ms`,
  `132.994 ms`, and `158.825 ms`, with request start skew below `3 ms`.
- Complete-set claims now require explicit selected-target verification. Use
  repeated `--expect-target-id` flags for every intended device; the runner
  writes `expected-targets.json` before any dry-run, build, install, launch,
  warm-prime, or rotation work. The current all-device guard run
  `20260607-runtime-role-switch-expected-iphone-guard-current` failed in
  `0.01s` because expected iPhone `00008101-000A68811E43001E` was absent from
  the selected targets, while the selected set only contained the three
  Androids, physical iPad 5, and macOS. The scoped visible-five rerun
  `20260607-runtime-role-switch-expected-visible-five-current` passed
  `expected-targets.json`, then stopped in `3.81s` at the then-current iPad
  `ios_profile_not_trusted` warm-prime blocker. The scoped warm-four rerun
  `20260607-runtime-role-switch-expected-four-local-current` passed explicit
  expected-target selection and all four master rotations in `3.93s`; the first
  rotation posted `set_role` to all four targets with request start offsets from
  `0.256 ms` to `1.038 ms`.
- The runner now writes per-rotation `phase-timings.json` and includes the same
  `phaseTimings` in rotation summaries. `20260607-runtime-role-switch-phase-timings-four-local`
  passed the guarded warm four-target matrix in `3.21s` and showed the real
  split: `set_role` took `145.694-239.867 ms`, promoted-master command
  readiness took `3.438-22.127 ms`, and connected-client verification dominated
  at `378.953-674.85 ms`.
- Slave registration no longer waits for a platform network snapshot before
  sending the first `deviceId` WebSocket message. The network payload is sent as
  an immediate deferred heartbeat, preserving network-status refresh without
  blocking master registration. The isolated proof is
  `test/slave/slave_client_registration_test.dart`; the rebuilt cold four-target
  proof `20260607-runtime-role-switch-fast-slave-registration-cold-four-local`
  passed after Android rebuild/install and macOS rebuild. First fresh rotations
  still pay app startup and route replacement churn, but the steady-state repeat
  `20260607-runtime-role-switch-fast-slave-registration-warm-immediate-repeat-four-local`
  passed all four guarded master rotations in `3.20s`: `set_role` was
  `157.024-243.046 ms`, request start skew stayed below `1.018 ms`,
  master-command readiness was `2.39-115.699 ms`, and connected-client
  verification was `294.225-564.773 ms`.
- Forced automation slaves now skip the duplicate network-readiness gate when a
  preferred master IP is supplied, master registration records the client before
  the asynchronous master network snapshot refresh, stale same-device socket
  closes cannot remove a newer client socket, and runtime role changes use
  zero-duration automation routes so old route transitions cannot dispose the
  newly promoted master. The chainable warm-prime artifact
  `20260607-runtime-role-switch-fast-forced-slave-connect-warm-prime-chainable-four-local`
  can be passed directly as `--warm-summary`. The hot-loop runner now supports
  `--repeat-role-switch-cycles` and skips the standby launcher entirely when
  `--require-warm-bridges` preflight has passed. Current-code cold proof
  `20260607-runtime-role-switch-async-ack-cold-four-local-fixed` passed two
  four-target cycles / 8 master rotations, but build/install/launch made it
  take `63.919s`; this is why repeat cold runs feel slow. That run also fixed a
  macOS direct-launch port bug: the debug app had been compiled for automation
  port `4762`, while the runner waited on `4770`. Cold direct-macOS targets are
  now normalized to the compiled default unless an already-running
  identity-matched bridge is adopted. The hot proof used
  `20260607-runtime-role-switch-async-ack-warm-prime-four-local` as the bridge
  source. Fully parallel
  `20260607-runtime-role-switch-current-code-parallel-skew10-stress5-four-local`
  passed five cycles / 20 rotations in `13.023s`; request-start skew was
  `0.238-3.058 ms` (avg `0.591 ms`), but connected-client verification had a
  `1914.965 ms` tail. Staged master-ready
  `20260607-runtime-role-switch-current-code-staged-skew10-stress5-four-local`
  passed the same 20 rotations in `9.746s` with
  `--stage-slaves-after-master-ready`: `set_role` averaged `304.915 ms`, and
  connected-client verification averaged `148.307 ms`. Async acknowledgement
  for both master and slaves
  `20260607-runtime-role-switch-async-ack-staged-skew10-stress5-four-local`
  was rejected as the default because it pushed master readiness later and took
  `13.279s`. The accepted split is synchronous acknowledgement for the promoted
  master plus async accepted acknowledgement for the parallel slave batch:
  `20260607-runtime-role-switch-slave-ack-poll25ms-staged-skew10-stress5-four-local`
  passed five cycles / 20 rotations in `8.118s` with 25 ms connected-client
  polling. Across all 20 rotations, `set_role` was `63.37-267.853 ms` (avg
  `161.328 ms`), slave-batch request-start skew was `0.33-1.928 ms` (avg
  `0.641 ms`), connected-client verification was `163.162-337.251 ms` (avg
  `239.845 ms`), and `set_role + connected_clients` was `243.832-542.688 ms`
  (avg `401.173 ms`). New connected-client instrumentation adds `registeredAt`
  and `masterServerStartedAt` to the automation payload; this evidence shows
  dispatch is already sub-millisecond and the remaining speed work is promoted
  master server startup plus client registration after server start.
- Physical iPhone hot role switching now has no-tooling Profile proof. Debug
  `Runner.app` cannot be fast-launched by `devicectl` because iOS logs
  "Cannot create a FlutterEngine instance in debug mode without Flutter tooling
  or Xcode" before Dart starts
  (`20260607-runtime-role-switch-iphone-console-launch`). The first current
  Profile install exposed the bridge at `192.168.178.168:4762`, proving the old
  `192.168.178.141` host was stale, but `automationTargetId` stayed blank
  because the native launch-config channel was not registered on the implicit
  Flutter engine. Retrying the Dart channel lookup alone did not fix that. After
  registering launch config and video metadata channels from
  `didInitializeImplicitFlutterEngine`, the profile build/install/launch proof
  `20260607-runtime-role-switch-iphone-engine-registrar-profile-scan` found an
  identity-matched iPhone bridge on attempt 1 with
  `automationTargetId=00008101-000A68811E43001E`. The iPhone-inclusive hot proof
  `20260607-runtime-role-switch-five-with-iphone-profile-hot` then passed
  Samsung G960F, Samsung S7 edge, Samsung S10e `RF8M90QE7LX`, iPhone 12 Pro, and
  macOS through two cycles / 10 master rotations in `4.382s` runner elapsed.
  Every selected device became master twice; request-start skew stayed below
  `3.373 ms`, `set_role` averaged `195.555 ms`, connected-client verification
  averaged `237.223 ms`, and the iPhone-as-master rotations verified the four
  expected slaves. The runner now has `--auto-ios-bridge-hosts`, enabled by the
  immediate role-switch shortcuts, which scans likely LAN hosts and accepts only
  `/healthz` responses with a matching `automationTargetId`. The cold iPhone
  rerun `20260608-auto-ios-host-fast-launch-five-hot` used
  `--prime-then-immediate-role-switch --fast-ios-launch` with no iPhone
  `--ios-host`: it launched the installed Profile app by device ID, discovered
  `http://192.168.178.168:4762`, and passed the five-device / 10-rotation matrix
  in `9.302s`. After adding the iPad trust-retry runner path,
  `20260608-prime-five-stress5-after-trust-retry-code` passed the same selected
  iPhone-inclusive set across five cycles / 25 rotations in `10.303s` after
  warm-prime; parallel request-start skew stayed below `2.51 ms`, `set_role`
  averaged `185.714 ms`, and connected-client verification averaged
  `222.491 ms`. A separate pure-immediate rerun,
  `20260608-hot-five-after-stress5-immediate`, passed two cycles / 10 rotations
  in `3.695s` once `/healthz` proved the iPhone bridge was warm. Treat
  `--prime-then-immediate-role-switch --fast-ios-launch` as the reliable
  one-command iPhone path when the iPhone bridge may be cold; use pure
  `--immediate-role-switch` only after verifying the iPhone bridge is currently
  warm. Successful warm role-switch runs now update
  `logs/verification-runs/latest-rotating-master-slave-warm-summary.json`, so
  normal `--immediate-role-switch` reruns can skip Flutter/ADB discovery and
  master-host probing without manually passing the previous run path. When that
  latest cache is used automatically, the runner also skips the default
  physical-iOS LAN scan unless `--auto-ios-bridge-hosts` is passed explicitly;
  stale cached iOS hosts fail in the identity-matched warm-bridge preflight. For
  a pinned prior run, add `--warm-summary
  logs/verification-runs/<last-good-run>/summary.json`: the current
  `20260608-warm-summary-prime-five-repeat` skipped Flutter/ADB discovery and
  master-host probing, launched only the cold iPhone bridge, and passed five
  cycles / 25 rotations in `9.167s`; the immediate warm-summary repeat
  `20260608-warm-summary-hot-five-repeat` passed the same 25 rotations in
  `8.806s` with no discovery, build, install, or launch. The latest-cache
  seed run `20260608-latest-cache-seed-five-hot` passed one full five-device
  rotation in `1.886s` and updated
  `latest-rotating-master-slave-warm-summary.json`; the follow-up
  `20260608-latest-cache-auto-five-hot` used that cache automatically, passed
  five cycles / 25 rotations in `8.482s`, and recorded `auto_latest` in
  `warm-summary-source.json`. After fixing the cache update guard so
  manually-constructed unit-test args cannot overwrite the durable latest cache,
  `20260608-latest-cache-reseed-five-hot-after-cache-fix` restored the cached
  five-device target set, and
  `20260608-latest-cache-short-command-five-hot-after-cache-fix` proved the
  short command with no `--warm-summary` and no `--target-id` list: five cycles
  / 25 rotations in `7.598s`, `auto_latest` source, warm preflight passed,
  `set_role` averaged `138.639 ms`, connected-client verification averaged
  `162.755 ms`, and max parallel slave request-start skew was `0.91 ms`.
  The runner now makes that staged-master / parallel-slaves path the immediate
  default, so `20260608-latest-cache-shortest-default-staged-five-hot` passed
  the same five-device / 25-rotation proof in `7.844s` without requiring
  `--stage-slaves-after-master-ready`. The explicit
  `--fully-parallel-role-switch` diagnostic probe
  `20260608-latest-cache-short-command-five-hot-fully-parallel-probe` also
  passed, proving all devices can receive `set_role` in one parallel batch, but
  it took `22.344s`; connected-client verification averaged `786.034 ms`
  because slaves raced the promoted master before its WebSocket server was
  ready. Use the fully parallel flag only for comparison/debugging.
- macOS standby uses the detached direct debug-app launcher for persistence
  across runner exits, but the direct app cannot change
  `HYDRACAM_AUTOMATION_PORT` at runtime because that value is a compile-time
  Dart define. Use port `4762` for cold direct-macOS standby unless an
  already-running identity-matched bridge is adopted. The older corrected
  warm-prime proof `20260607-runtime-role-switch-direct-macos-warm-prime-four-local`
  completed in `1.45s` and left matching Android/macOS warm bridge identities.
- The remaining Android + macOS warm-run delay was macOS process persistence,
  not compile/deploy. `20260607-macos-standby-persistence-experiment` showed a
  direct macOS app launched as a child of the Python runner disappeared as soon
  as the parent process exited. Launching direct macOS standby in a detached
  process group keeps the automation bridge alive for later runs while still
  preserving explicit cleanup for non-reuse runs. After that fix, the current
  Android + macOS proof
  `20260607-runtime-role-switch-android-macos-shared-bind-current` passed all
  three master rotations in `87.22s` including Android build/install and macOS
  launch. The patched-runner warm prime
  `20260607-runtime-role-switch-android-macos-detached-runner-warm-prime`
  relaunched macOS, reused both Android bridges, passed all three rotations in
  `3.98s`, and left macOS `/healthz` alive after the Python runner exited. The
  immediate repeat
  `20260607-runtime-role-switch-android-macos-detached-runner-warm-immediate`
  then passed the same three rotations in `2.10s` wall time. Its parallel
  `set_role` calls were `132.486 ms`, `118.891 ms`, and `117.939 ms`, and macOS
  `/healthz` remained alive with `automationTargetId=macos` after completion.
- Capture-enabled runtime-switch automation is faster but not yet passing as a
  full matrix. `20260607-runtime-role-switch-capture-accelerated` adds
  per-stage `progress.ndjson`, concurrent stage waits, configurable capture
  timeouts, and a short recording-ready cap so failed slaves no longer inflate a
  `--record-seconds 2` run into multi-minute video. That run still failed
  because macOS did not produce slave media and one Android slave missed
  `isRecording`; treat it as acceleration/debug evidence, not capture proof.
- `20260618-1750-automation-bridge-malformed-request` hardens the automation
  bridge command endpoint so malformed JSON request bodies return
  `400 invalid_request` and do not invoke the registered command handler instead
  of being logged as generic `500 bridge_failure`. This is Tier D HTTP-boundary
  unit coverage; keep live role-switch and capture proof separate.
- Reusing an already-running stale iPad bridge proved the parallel `set_role`
  calls work (`456.621 ms` and `284.267 ms`), but iPad-as-master failed because
  the stale app exposed only `set_role` and not `connected_clients`. Relaunching
  the current build fixed that.
- Android skip-install proof against Samsung S10e `RF8M90QE7LX` failed because
  the installed APK does not expose `set_role`. A current automation APK must be
  built and installed before Android can participate in runtime role switching;
  this was fixed for `RF8M90QE7LX` by building with
  `--android-ndk-version 27.0.12077973`.
- iPhone 12 Pro runtime-switch proof is no longer pending for Profile
  automation. Prefer the identity-based auto host scan in immediate and
  prime-then-immediate role-switch runs; it writes
  `ios-bridge-host-prefill.json` and `ios-bridge-host-adoption.json`, and fails
  unless the discovered bridge reports
  `automationTargetId=00008101-000A68811E43001E`. Do not reuse the stale
  `192.168.178.141` host from older capture evidence.
- Physical iPad Profile deployment is now unblocked after the iPad update to
  iOS 17.7.11. Earlier 2026-06-08 runs
  `20260608-ipad-profile-install-fallback-warm-prime`,
  `20260608-ipad-warm-prime-after-default-staged-with-host`, and
  `20260608-all-selected-trust-retry-short` correctly classified the old blocker
  as `ios_profile_not_trusted`. The current evidence pack
  `20260608-0309-ipad-ios17711-profile-compile-deploy-rerun` shows a fresh
  automation Profile compile passing, `devicectl install app` succeeding for
  `com.vectorblanco.hydracam.dev`, the installed app exposing
  `automationTargetId=8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` at
  `http://192.168.178.104:4762/healthz`, and post-install Flutter, xctrace, and
  CoreDevice all seeing the iPad paired/online. The first post-install
  warm-prime runner returned `ios_warm_bridge_missing` before the bridge was
  reachable; the follow-up run
  `20260608-ipad-ios17711-warm-bridge-confirmed` passed with zero missing warm
  bridges. Do not update the durable latest warm-summary cache from scoped
  one-device iPad runs; rerun the full selected-set loop before claiming a new
  six-target rotation benchmark.
- `20260609-0021-ipad-physical-release-profile-smoke` refreshed this proof with
  the currently connected iPad over the wired link-local host
  `169.254.193.202`. The run built and installed the Profile app, warmed the
  identity-matched bridge, saved an iPad-origin automation screenshot, then
  passed a one-device master capture flow with one photo and one 2.135 second
  1920x1080 H.264 MP4 copied from the app container. It also found a
  runtime-screenshot follow-up after `set_role` into master; that is now fixed
  and proved by
  `20260609-0120-ipad-runtime-screenshot-boundary-route-replacement`, which
  moved the automation `RepaintBoundary` around the `MaterialApp` navigator and
  showed `capture_screenshot` succeeding on the updated iPad Profile app before
  and after `set_role`.
- Historical pre-update iPad notes: when this iPad was still on iOS 15.6.1 and
  visible to `xcdevice` but not usable through `devicectl`, the runner added an
  explicit `--xctrace-ios-launch` path.
  `20260607-ipad-xctrace-launch-live-poll` proved xctrace could launch the
  installed iPad app and pass `HYDRACAM_AUTOMATION_*` environment values, but
  the installed app produced no bridge. After an explicit automation debug iOS
  build and IPA install, `20260607-ipad-explicit-automation-ipa-xctrace` proved
  the install path worked but xctrace reported the iOS 15.6.1 app could not
  launch because the signing profile was not explicitly trusted. The runner
  evidence `20260608-ipad-profile-install-fallback-warm-prime` automated that
  path with `--ios-profile-build-install`, falling back from `devicectl` to IPA
  packaging plus `flutter install --use-application-binary`, then reporting
  `ios_profile_not_trusted` from xctrace instead of hanging in `flutter run`.
  Those `devicectl` limitations are no longer current after the iOS 17.7.11
  deployment rerun.

Next multi-device confidence gaps: keep the warm bridge map current, rerun the
full selected-set loop now that the iPad iOS 17.7.11 bridge is warm, rerun with
capture enabled where cameras are expected to work, investigate macOS-as-slave
media capture, and keep the iPhone Profile app installed for fast no-tooling
launch. Use warm-only mode for immediate iteration, warm-prime mode only when
intentionally launching or refreshing a missing device, and repeated
`--expect-target-id` flags whenever
the run is meant to prove a complete selected-device set.

## Android Device Support Floor

Decision date: 2026-06-06.

HydraCam's active Android validation and distribution target starts at Android
API 24. Devices on Android 6.0/API 23 or older are deprecated for this repo and
should be treated as unsupported hardware unless a new product decision
explicitly reopens legacy-device support.

The Lenovo Phab2/PB2-690M is deprecated:

| Field | Value |
| --- | --- |
| Device | Lenovo Phab2 / Lenovo PB2-690M |
| Observed USB serial | `9d94c365` |
| OS/API | Android 6.0.1 / API 23 |
| 2026-06-06 outcome | Current HydraCam debug APK install failed with `INSTALL_FAILED_OLDER_SDK`, then the device dropped off ADB. |
| Decision | Do not build a lower-SDK Flutter variant for this device; the time and dependency/toolchain cost is not worth it. |

Context: the current debug APK built on 2026-06-06 reports `minSdk=24`.
Supporting the Lenovo would require a separate legacy Flutter/toolchain lane
before the Flutter API-24 floor plus plugin downgrades or feature removal. This
is now explicitly out of scope.

Android devices used for current validation should be API 24 or newer. The
Samsung Galaxy S7/SM-G935F on Android 8.0/API 26 remains a usable low-end
Android target after current app launch, runtime permission verification, and
the SM-G935F compatibility camera mode above.

## Current Goals

1. Make the app reliable on Android and iOS through repeatable real-device
   smoke tests. The prior iOS physical-device white-screen blocker is closed by
   newer iPhone/iPad evidence; do not reopen it without a fresh reproducible
   failure and logs.
2. Keep release/beta distribution paths ready for TestFlight plus Google Play
   internal, closed testing, and production-draft uploads, but do not claim
   production readiness without real device smoke tests.
3. Build a platform compatibility matrix across iOS, Android, macOS, Windows,
   Linux, and web as support expands.
4. Enable repeatable testing for master/slave session flow, capture, storage,
   upload, reconnect, low battery, and low storage behavior.

## Roadmap From Sheet Import

### Active Mobile Themes

- Session integrity: reconnect behavior, stale session state, joining existing
  sessions, and preventing media from crossing session boundaries.
- iOS reliability: client/server networking behavior, disconnects, navigation
  artifacts, signing/profile/release launch behavior, and regression coverage
  for the fixed iPad no-flash camera path.
- Upload and media handling: upload failure UI, cancel/requeue upload, upload
  progress/time estimates, version metadata, gallery import, and heavy video
  loading.
- Device/network awareness: show network identity, device IP/hardware/app
  version, disconnected clients, and multiple camera groups on the same LAN.
- Recording safety: critical battery autostop, storage autostop, foreground
  behavior, and synchronized time.
- Camera capture configuration: local per-device lens preference and target
  video profiles are now app settings; verify actual resolution/fps on iPhone
  12 Pro and Samsung S7/S10e before using them for production claims.
- Auto-record/unattended flow: devices start recording automatically when a
  slave connects to a master with an active session.
- Mobile authentication: restore valid Auth0 credentials on app start, persist
  refresh-capable credentials securely, end both local and browser/Auth0 sessions
  on logout, recover Android login after process death, and decide whether
  Android should use native Credential Manager/Sign in with Google for the
  account-picker experience users expect from other apps.
- Desktop/webcam support: desktop is monitoring/development-only for now; webcam
  capture is deferred by the scope decision below.
- User/player assignment: attach players/users to sessions and support mid
  session player additions.

### External Backend/Web Dependencies

- Material retrieval endpoint and slow heavy-video gallery behavior.
- Backend upload metadata fields and duration fixes.
- SignalR hub, Azure queue, delivery package, queue processors, and live
  monitoring.
- QR/user request flow for unattended court activation.
- GDPR document hosting and consent gating if implemented outside the mobile
  app.

### Future Product Ideas

These came from `SYSTEM FEATURES` and should stay roadmap-only until explicitly
pulled into active mobile work:

- AI rally segmentation, shot classification, ball/wall contact inference, heat
  maps, player body position, errors/winners location, and 3D reconstruction.
- Video referee features: live human review, AI decisioning, democratic review,
  and instant replay.
- Games and fan-facing experiences: guess-the-next-shot, referee game, loud
  calls, and score/VAR overlays.
- External refereeing/annotation APIs, user annotation, strategy suggestions,
  ball speed, step/distance counters, and padel/squash edge-case rulings.

## Recent iOS Evidence

- `logs/verification-runs/20260609-0355-signing-jose-keepeyeonball-ios-redeploy/`:
  moved iOS Profile/Debug/TestFlight defaults to Apple ID
  `jose@keepeyeonball.com`, team `4RRY2QT7H8`, and bundle
  `com.keepeyeonball`. Physical iPad and iPhone Profile build/install attempts
  both failed before install with `No Accounts: Add a new account in Accounts
  settings` and missing `iOS Development` certificate/private key for team
  `4RRY2QT7H8`. This initial blocker is superseded by the follow-up run below;
  TestFlight still needs App Store Connect upload credentials.
- `logs/verification-runs/20260609-0414-signing-jose-keepeyeonball-ios-redeploy-after-account/`:
  after the Xcode account update, confirmed a Keepeyeonball Apple Development
  certificate, built Profile `com.keepeyeonball`, installed/launched it on iPad
  and iPhone through `devicectl`, found the iPhone automation bridge at
  `192.168.178.168:4762`, copied an iPhone automation screenshot, and exported
  App Store IPA `build/ios/ipa/HydraCam.ipa` signed by a cloud-managed Apple
  Distribution certificate. The iPad app installed and launched, but its
  automation bridge did not answer on the known Wi-Fi/link-local addresses or
  scanned subnets. TestFlight upload still needs App Store Connect upload
  credentials.
- `logs/verification-runs/2026-06-06-iphone-personal-team-debug/`: iPhone 12
  Pro / iOS 26.4.2 debug run launched through `flutter run`, received camera
  and microphone permissions, reached master mode, created session ID `466` /
  GUID `f60e4a7a-ec8e-4897-8943-43dc0325e2d6`, captured and uploaded a photo,
  and started video recording. Limitation: this used a personal development
  team because the organization team signing state was expired for new iPhone
  debug signing.
- `logs/verification-runs/20260606-2310-ipad-capture-failure-trace-and-repro/`:
  physical iPad / iOS 15.6.1 validation passed after upgrading within the
  current camera line (`camera` 0.11.4 and `camera_avfoundation` 0.9.23+2).
  The repro captured one photo and one video, returned recording state to
  false after stop, and left a repeatable trace/repro path.
- 2026-06-07 user follow-up: manual iPad and iPhone 12 testing appears to be
  working OK.
- `logs/verification-runs/20260607-camera-settings-device-matrix/ipad-autoBack-standard1080p30/`:
  physical iPad / iOS 15.6.1 automation capture passed with local settings
  `autoBack` + `standard1080p30`, one photo, one video, and recording false
  after stop. Limitation: saved-video metadata was unavailable.
- `logs/verification-runs/20260607-camera-settings-device-matrix/iphone12-devicectl-launch-second.log`:
  iPhone 12 Pro / iOS 26.4.2 retest was blocked because the device was locked;
  SpringBoard denied launch of `com.vectorblanco.hydracam.dev`.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/ipad-autoBack-standard1080p30-after-ios-metadata/`:
  physical iPad / iOS 15.6.1 automation capture passed again with local
  settings `autoBack` + `standard1080p30`, one photo, one video, and recording
  false after stop. Limitation: saved-video metadata was still unavailable.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/iphone12-ultraWide-sport1080p60-after-fixes/`:
  iPhone 12 Pro / iOS 26.4.2 `ultraWide` + `sport1080p60` retest built and
  signed the debug app, but Flutter/Xcode timed out starting the debug session.
  A direct `devicectl` launch of `com.vectorblanco.hydracam.dev` was denied
  because the phone was locked, so the automation bridge was not discovered.
- `logs/verification-runs/20260607-new-devices-rerun/iphone12pro-ultrawide-sport1080p60/`:
  iPhone 12 Pro / iOS 26.5 passed debug automation capture with local settings
  `ultraWide` + `sport1080p60`, selected camera
  `com.apple.avfoundation.avcapturedevice.built-in_video:5`, one photo, one
  video, and recording false after stop. Limitation: saved-video metadata was
  unavailable.
- `logs/verification-runs/20260607-new-devices-rerun/iphone12pro-ultrawide-detail4k30/`:
  iPhone 12 Pro / iOS 26.5 passed debug automation capture with local settings
  `ultraWide` + `detail4k30`, the same selected 0.5x camera id, one photo, one
  video, and recording false after stop. Limitation: saved-video metadata was
  unavailable.
- `logs/verification-runs/20260607-1501-ios-icon-profile-launch/`:
  Profile build and install passed for bundle ID `com.vectorblanco.hydracam.dev`
  using personal development team `8T78Y2X37H`. A foreground no-tooling launch
  was denied because the iPhone was locked, but a no-tooling `--no-activate`
  launch succeeded and started `Runner.app/Runner` process ID `1172`. Manual
  Home Screen icon video remains pending until the iPhone is unlocked.
- `logs/verification-runs/20260607-runtime-role-switch-iphone-console-launch/`:
  fast-launching a debug iPhone `Runner.app` through `devicectl` started a
  process, but iOS logged that a debug Flutter engine cannot be created without
  Flutter tooling or Xcode. Use Profile for no-tooling iPhone automation runs.
- `logs/verification-runs/20260607-runtime-role-switch-iphone-current-profile-install-fast-launch-scan/`
  and
  `logs/verification-runs/20260607-runtime-role-switch-iphone-profile-launch-config-retry-scan/`:
  current Profile builds exposed an iPhone bridge at `192.168.178.168:4762`, but
  `automationTargetId` was blank because the native launch-config channel was
  not registered on the implicit Flutter engine. Dart-side retrying alone was
  insufficient.
- `logs/verification-runs/20260607-runtime-role-switch-iphone-engine-registrar-profile-scan/`:
  after registering native channels from `didInitializeImplicitFlutterEngine`,
  Profile build/install/launch produced an identity-matched iPhone bridge at
  `192.168.178.168:4762` on attempt 1.
- `logs/verification-runs/20260608-auto-ios-host-fast-launch-five-hot/`:
  no manual iPhone host was supplied. The runner fast-launched the installed
  iPhone Profile app by device ID, scanned likely LAN hosts, matched
  `automationTargetId=00008101-000A68811E43001E` at
  `192.168.178.168:4762`, and passed the five-target role-switch matrix in
  `9.302s`.
- `logs/verification-runs/20260608-auto-ios-host-warm-immediate-five-hot-rerun/`:
  warm immediate repeat passed the same five selected targets with no manual
  iPhone host and no iPhone launch in `3.781s`.
- `logs/verification-runs/20260608-all-selected-auto-iphone-ipad-xctrace-rerun/`:
  all six selected targets passed expected-target validation and iPhone host
  adoption, then stopped before rotations because the iPad xctrace launch did
  not expose an automation bridge at `192.168.178.104:4762`.

## Recent Android Evidence

- `logs/verification-runs/20260609-1405-s7-higher-resolution-compat/`:
  Samsung S7 edge / Android 8 preserves requested `standard1080p30` on the
  SM-G935F compatibility path, uses preset-default FPS, captures a copied
  1920x1080 JPEG, and records a copied 1920x1080 MP4. This supersedes the
  older S7 480p workaround and the June 7 baseline S7 photo timeouts for
  direct camera-open/capture proof.
- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_023947-s10e-autoBack-standard1080p30/`:
  Samsung S10e / Android 12 applied `autoBack` + `standard1080p30`, captured one
  photo and one video, and logged recorded video metadata as `1920x1080,
  unknown fps, 3966 ms`. Limitation: automation `end_session` left the local
  session active.
- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_023637-s10e-autoBack-sport1080p60-rerun/`:
  Samsung S10e / Android 12 applied `autoBack` + `sport1080p60`, then capture
  stalled with Samsung/Exynos camera request and buffer errors.
- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_024916-s7-autoBack-standard1080p30/` and
  `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_024615-s7-autoBack-sport1080p60-rerun2/`:
  Samsung S7 edge / Android 8 applied the requested settings, but both baseline
  and 60 fps runs failed before photo/video with Camera3/Exynos buffer
  timeouts.
- `logs/verification-runs/20260607-camera-settings-device-matrix/xiaomi-2201116pg-install-block/adb-install-rerun.log`:
  Xiaomi 2201116PG / Android 13 install was blocked by
  `INSTALL_FAILED_USER_RESTRICTED`.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_032251-s10e-autoBack-standard1080p30-after-batch/`:
  Samsung S10e / Android 12 applied `autoBack` + `standard1080p30`, captured one
  photo and one video, logged recorded video metadata as `1920x1080, unknown
  fps, 4014 ms`, and ended the local automation session cleanly.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607-final-s10e-autoBack-standard1080p30/20260607_035355-s10e-autoBack-standard1080p30-final-smoke/`:
  Samsung S10e / Android 12 final current-build smoke reinstalled the debug APK,
  applied `autoBack` + `standard1080p30`, captured one photo and one video,
  logged recorded video metadata as `1920x1080, unknown fps, 3866 ms`, and ended
  inactive.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033121-s10e-autoBack-sport1080p60-clean-timeout/`:
  Samsung S10e / Android 12 applied `autoBack` + `sport1080p60` and failed with
  a bounded 12 second photo-capture timeout. The earlier disposed-controller
  crash did not recur.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033406-s7-autoBack-standard1080p30-after-batch-timeout/` and
  `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033527-s7-autoBack-compat720p30-after-batch-timeout/`:
  Samsung S7 edge / Android 8 applied the requested camera `0` settings, then
  failed before photo with bounded 12 second timeouts at both 1080p30 and
  720p30. Treat S7 as a baseline CameraX/device-path blocker before spending
  more time on 4K or 60 fps.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/xiaomi-2201116pg-install-block/adb-install-rerun.log`:
  Xiaomi 2201116PG / Android 13 install retry remains blocked by
  `INSTALL_FAILED_USER_RESTRICTED`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_144440-new-rf8m21j8xrt-standard1080p30/`:
  newly connected Samsung S10e / Android 12 (`RF8M21J8XRT`) applied
  `autoBack` + `standard1080p30`, captured one photo and one video, ended the
  automation session, and logged recorded video metadata as `1920x1080,
  unknown fps, 3966 ms`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_144222-new-g960f-standard1080p30/` and
  `logs/verification-runs/20260607-new-devices-rerun/20260607_144932-new-g960f-compat720p30/`:
  newly connected Samsung SM-G960F / Android 10 applied camera `0` settings and
  initialized the camera, but both 1080p30 and 720p30 failed before photo save
  with CameraX `ImageCaptureException: Not bound to a valid Camera`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_145107-s7-edge-datasaver480p30-rerun/`:
  Samsung S7 edge / Android 8 applied `autoBack` + `dataSaver480p30`, selected
  camera `0`, initialized, then timed out after 12 seconds before photo save.
  Logcat shows repeated ExynosCamera3 wait timeouts plus Camera2 reopen /
  `ERROR_MAX_CAMERAS_IN_USE` errors.

## Release Blockers

- 2026-06-09 beta-first readiness cleanup implemented the local release wrapper
  fix, branded launch placeholders, fastlane Ruby/Bundler wrapper, generated
  backup cleanup, and store privacy/metadata checklist. Local static gates
  passed in the implementation turn: `flutter analyze`, `flutter test`,
  `git diff --check`, `scripts/build_store_artifacts.sh all` with default
  versioning, and `BUILD_NAME=1.4.0 BUILD_NUMBER=17
  scripts/build_store_artifacts.sh all`, with `SKIP_CHECKS=1` on the build-only
  wrapper runs after static validation passed. The current verified default
  `1.4.0+18` Android artifact SHA-256 is
  `d570e6ebe507ad2a6f2de5c499cf5bd2cd2f162932bde63e47a728b51c75c8d9`; the
  historical pre-cleanup iOS artifact SHA-256 is
  `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`.
  The pre-privacy-manifest `1.4.0+17` wrapper validation artifacts were Android
  `4de67e7df246b9c88c99c6598d887992a0f9d7e892f282a102d972dfd67a6b02` and iOS
  `7ec7a6a90e064cc6b1cac12d5c5ccd8adf2972926b05251eca67ad7f610c6895`;
  rerun the override before uploading build number 17.
- 2026-06-09 follow-up cleaned iOS store permission metadata by removing
  release-visible Dart VM Bonjour services from `Info.plist`, replacing casual
  photo-library copy with review-grade descriptions, and adding bundled
  `ios/Runner/PrivacyInfo.xcprivacy` declarations for app-functionality data
  collection plus required-reason APIs. A later follow-up added
  `ITSAppUsesNonExemptEncryption=false` after a source scan found no custom
  non-exempt cryptography. The current follow-up also removed bundled
  placeholder/test court fallback data from the master court picker and added
  `test/constants_release_hygiene_test.dart`; regenerated launcher icons from
  the branded source asset, removed obsolete unreferenced JPEG-backed iOS icon
  files, and updated the launcher-icon config to `flutter_launcher_icons`; full
  `flutter test` now passes with `284` tests and `1` skipped. The follow-up
  also replaced the default pubspec description, removed Android release
  debug-signing fallback, added `url_launcher` for the pre-login account
  privacy/support/deletion URL handoff, declared `url_launcher_android`
  `^6.3.32` for the current AGP `8.11.1` release stack, and added preflight
  checks for preserved app IDs, fastlane Appfile targets, Android SDK floor,
  Android target/compile SDK policy, Login screen
  privacy/support/account-deletion paths and Dart defines, configured upload
  keystore, AAB signer fingerprint, AGP-aware `url_launcher_android`
  compatibility, app-specific Auth0 redirect schemes, and HydraCam-branded web
  metadata. The
  current code/manifest path uses `com.keepeyeonball://login-callback` on iOS
  and the Gradle `appAuthRedirectScheme` placeholder resolves to
  `com.amaia23.hydracam://login-callback` on Android, replacing the old generic
  `com.hydracam` callback scheme. The new
  `scripts/check_store_readiness.sh local` preflight fails on missing local
  Apple/iOS Distribution signing identity, verifies launcher icon PNG assets,
  verifies the Android upload certificate path, and warns that no current iOS
  IPA exists plus missing external submission values. The same script in
  `upload` mode fails until the IPA is rebuilt,
  `APP_STORE_CONNECT_API_KEY_PATH`,
  `GOOGLE_PLAY_JSON_KEY`, `HYDRACAM_PRIVACY_POLICY_URL`,
  `HYDRACAM_SUPPORT_URL`, and `HYDRACAM_ACCOUNT_DELETION_URL` are set to usable
  values, and the URLs are public non-placeholder HTTPS URLs. Final upload
  artifacts must be rebuilt with `HYDRACAM_PRIVACY_POLICY_URL`,
  `HYDRACAM_SUPPORT_URL`, and `HYDRACAM_ACCOUNT_DELETION_URL` set so the
  published policy, support, and deletion pages are compiled into the release
  app; the wrapper and fastlane lanes now write `*.store-metadata.tsv`
  sidecars, and upload preflight fails if the sidecar hash, build override, or
  compiled store URLs do not match the artifact and current environment. Auth0
  Allowed Callback URLs and Allowed Logout URLs must also be updated to include
  the two app-specific callback URLs before beta login testing.
- 2026-06-18 store-readiness mode-scope note:
  `logs/verification-runs/20260618-1851-store-readiness-mode-scope/` adds a
  fixture regression for `scripts/check_store_readiness.sh upload-ios` and
  `upload-android` so TestFlight-only checks do not emit Android-only blockers
  and Google Play-only checks do not emit iOS-only blockers. The live
  diagnostics still fail on lane-appropriate blockers: iOS lacks a current IPA,
  local Distribution/App Store Connect upload credentials, and public store
  URLs; Android reports stale/mismatched AAB metadata plus missing
  `GOOGLE_PLAY_JSON_KEY` and public store URLs.
- 2026-06-21 Android release helper update: `scripts/google_play_release.sh`
  is the track-aware Android upload entrypoint for Google Play `internal`,
  `closed_beta`, and `production_draft` lanes. `scripts/check_store_readiness.sh`
  accepts matching Android-only preflight aliases `play-internal`,
  `play-closed`, and `play-production`, and
  `scripts/google_play_internal_release.sh` remains a compatibility wrapper for
  the internal testing lane.
- 2026-06-18 skipped singleton-test cleanup:
  `logs/verification-runs/20260618-1620-camera-singleton-reset-test-hook/`
  removes the remaining skipped `CameraServiceSingleton` uninitialized-guard
  test by adding a testing-only singleton reset hook. Focused singleton coverage,
  analyzer, and the full `flutter test --no-pub` suite passed with `431` tests
  and no skipped tests.
- Android local distribution signing/build is no longer the blocker:
  `logs/verification-runs/20260609-0405-amaia23-android-developer-profile-recovery/summary.md`
  proves a signed AAB built with the recreated AMAIA23/HydraCam upload
  certificate. Remaining Android store work is external account/profile
  recovery: `vectorblanco@gmail.com` currently lands on Play Console signup, so
  complete the `jose@keepeyeonball.com` Google sign-in, verify whether it owns
  the AMAIA23 Play Console developer account/app, then either invite
  `vectorblanco@gmail.com`, request/upload-key reset with the recorded
  certificate fingerprint, or create the organization developer profile and
  register `com.amaia23.hydracam`.
- Android toolchain future-compatibility is no longer a source-update blocker:
  the tracked Android toolchain is now Gradle `8.14.5`, Android Gradle Plugin
  `8.11.1`, Kotlin `2.2.20`, and the settings-based Flutter Gradle plugin
  loader. The remaining release concern is artifact proof after the toolchain
  bump: rebuild the signed Android AAB and rerun
  `scripts/check_store_readiness.sh local` before treating the current Android
  source as beta-upload ready.
- iOS local signing/build is no longer the primary blocker: current evidence
  proves the Keepeyeonball team, bundle, App Store IPA export, and recovered
  physical iPhone+iPad Profile automation lane. Remaining iOS store work is
  external App Store Connect upload authentication plus release-lane user smoke
  and two-device capture workflow evidence before production.
- Store privacy answers must be reviewed against current code and backend
  behavior before submission.
- Android and iOS real-device smoke tests must pass on the exact release lane.
- Camera lens/profile claims still need production-grade proof. iPhone 12 Pro
  ultra-wide 1080p60 and 4K30 now pass in debug automation, and iPhone Profile
  automation launch is proven for role switching, but iOS saved-video metadata
  remains unavailable. Samsung S7 rear-wide `standard1080p30` now has direct
  1920x1080 photo/video proof; S7 rear-wide 1080p60/4K30 remains unproven.
- Human-user login must survive app restart and Android process-death during
  browser authentication, and logout/account switching must be validated before
  release claims depend on user identity.
- A two-device HydraCam flow must pass on the same local network or hotspot:
  discovery, slave connection, photo capture, video start/stop, local save,
  upload queue, and session end.
- Do not spend release-blocker time on Android 6.0/API 23 or older hardware.
  The Lenovo Phab2/PB2-690M path is deprecated and should not reopen unless a
  product owner explicitly reverses the support floor decision.
- Docs and Linear issues must not imply backend/Azure work is complete unless it
  has current proof outside this mobile repo.

## Desktop/Webcam Scope Decision

Decision date: 2026-06-06.

This completes the imported backlog decision task for `JAVI IMMEDIATE BACKLOG`
rows 76, 83, and 103.

| Platform | Current scope | Capture support |
| --- | --- | --- |
| Android | Primary mobile target for master/slave capture and validation. | In scope. |
| iOS | Primary mobile target; recent iPhone 12 Pro and physical iPad evidence shows launch/capture works in debug/test flows. | In scope. |
| macOS/Windows/Linux | Development, diagnostics, monitoring, and possible viewer/control workflows only. | Deferred. |
| Web | Future viewer/control or portal surface only. | Deferred. |

Desktop/webcam capture is not an active implementation target in this mobile
repo. Reopening that scope would require a separate design for camera APIs,
file/gallery persistence, permission behavior, packaging, and cross-platform
test coverage. Until then, do not create Linear issues for generic "use webcam"
or "Windows version" rows unless a concrete non-capture monitoring/control
workflow is requested.

2026-06-07 update: macOS native controller support is now enabled for debug
builds without implementing desktop webcam capture. The app skips unsupported
`permission_handler` startup calls on macOS, defaults local master recording off
on macOS unless the user explicitly enables it, signs debug/release macOS
targets with local-network/media/location entitlements, and uses a mock local
camera path so controller flows can run while real desktop capture remains
deferred.
