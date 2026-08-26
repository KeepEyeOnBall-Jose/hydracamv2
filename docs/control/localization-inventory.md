# Localization Inventory

Last reviewed: 2026-06-09 (content dated 2026-06-09).
Updated: 2026-06-09.

This file tracks the first HydraCam localization slice and the remaining
user-facing strings that still need extraction. The app now supports Flutter
locales `en`, `es`, `de`, and `pl` through `gen-l10n`; the non-English values
are seed translations pending product review.

## Localized in This Pass

- Flutter localization framework: `l10n.yaml`, `lib/l10n/app_*.arb`, generated
  `AppLocalizations`, and `flutter_localizations`.
- App language override: Settings dropdown with system default, English,
  Spanish, German, and Polish.
- Settings screen copy: Settings title, Preferences, language row, capture
  settings headings/descriptions, storage location row, upload toggles,
  auto-record row, screen auto-off, timer duration, and flash announcements.
- App-shell entry points: menu labels for Device Info, Settings, Camera
  Selection, Location Info, Logs, Uploader Info, App Version, Login, plus the
  app-version dialog labels.
- Apple locale declaration: `CFBundleLocalizations` in iOS and macOS plists for
  `en`, `es`, `de`, and `pl`.

## Remaining Flutter UI Strings

- Master/session control: `lib/master/master_screen.dart` still has session
  actions, recording/capture snackbars, device-list labels, court warnings, and
  end-session dialog copy.
- Slave and recording surfaces: `lib/slave/slave_screen.dart` and
  `lib/screens/master_video_recording_screen.dart` still have upload/preview
  tooltips and recording controls.
- Media and upload UI: `lib/widgets/media_list_widget.dart`,
  `lib/screens/uploader_info_screen.dart`, and upload status rows still have
  upload-state labels, action tooltips, and estimated-time text.
- Gallery import: `lib/widgets/add_gallery_media_button.dart`,
  `lib/widgets/media_filter_dialog.dart`, and `lib/screens/media_selection_screen.dart`
  still have filter labels, import messages, and dialog actions.
- Session browsing/details: `lib/screens/previous_sessions_screen.dart`,
  `lib/screens/session_details_screen.dart`, and `lib/screens/sessions_screen.dart`
  still have session metadata labels, load/failure snackbars, media detail
  dialogs, and empty/error states.
- Camera/device utilities: `lib/screens/camera_selection_screen.dart`,
  `lib/screens/camera_setup_preview_screen.dart`,
  `lib/widgets/court_selection_widget.dart`, and `lib/services/alert_utils.dart`
  still have camera instructions, device/location dialogs, court selectors, and
  generic dialog actions.
- Auth/log/location screens: `lib/screens/login_screen.dart`,
  `lib/screens/log_screen.dart`, `lib/screens/courts_screen.dart`, and
  `lib/screens/sports_centers_screen.dart` still have screen titles, loading
  states, and failure messages.
- Runtime service snackbars: `lib/services/battery_service.dart` and
  `lib/services/storage_service.dart` still have user-visible low/critical
  battery and storage warning copy.

## Native Platform Strings

- iOS `ios/Runner/Info.plist`: camera, microphone, location, local-network, and
  photo-library usage descriptions still need localized `InfoPlist.strings`
  files for `en.lproj`, `es.lproj`, `de.lproj`, and `pl.lproj`.
- macOS `macos/Runner/Info.plist`: camera, microphone, location, local-network,
  and photo-library usage descriptions still need localized
  `InfoPlist.strings` files for the same locales.
- Android manifest/resource prompt strings should be inventoried in the next
  pass before adding `res/values-*/strings.xml`; no Android native copy was
  localized in this pass.

## Explicitly Excluded

- `LogService` messages, trace labels, and diagnostics text intended for
  developers or evidence packs.
- Automation bridge command names, JSON keys, route names, and protocol values.
- Stored preference keys, including legacy `autograbadoMode` and
  `localeOverride`.
- Historical evidence directory names and control-doc proof paths.
- Backend API fields, session GUID/device ID labels in payloads, and upload
  contract metadata.
