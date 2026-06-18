import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/l10n/app_localizations.dart";
import "package:hydracam/screens/settings_screen.dart";
import "package:hydracam/services/app_locale_service.dart";
import "package:shared_preferences/shared_preferences.dart";

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  AppLocaleService? localeService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(localeService: localeService),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      "settings screen shows capture settings instead of camera quality",
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpSettingsScreen(tester);

    expect(find.text("Capture Settings"), findsOneWidget);
    expect(find.text("Camera Lens"), findsOneWidget);
    expect(find.text("Video Profile"), findsOneWidget);
    expect(find.text("1080p at 30 fps"), findsOneWidget);
    expect(find.text("Standard 1080p30"), findsNothing);
    expect(find.text("Auto back camera"), findsOneWidget);
    expect(find.textContaining("Target: 1080p at 30 fps"), findsOneWidget);
    expect(find.text("Camera Quality"), findsNothing);
  });

  testWidgets("settings screen exposes disabled auto-record toggle",
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpSettingsScreen(tester);

    expect(find.text("Auto-record mode"), findsOneWidget);
    expect(find.text("Autograbado mode"), findsNothing);
    final autoRecordSwitch = find.byKey(const ValueKey("autoRecordMode"));
    expect(autoRecordSwitch, findsOneWidget);
    expect(tester.widget<Switch>(autoRecordSwitch).value, isFalse);

    await tester.ensureVisible(autoRecordSwitch);
    await tester.pumpAndSettle();
    await tester.tap(autoRecordSwitch);
    await tester.pumpAndSettle();

    expect(
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.getBool("autograbadoMode"),
        ),
        isTrue);
  });

  testWidgets("settings screen explains current storage location",
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpSettingsScreen(tester);

    expect(find.text("Storage location"), findsOneWidget);
    expect(find.text("Internal app storage"), findsOneWidget);
    expect(find.text("SD card selection not configured"), findsOneWidget);
  });

  testWidgets("settings language dropdown stores Polish override",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localeService = AppLocaleService();
    await localeService.load();

    await _pumpSettingsScreen(tester, localeService: localeService);

    final languageDropdown =
        find.byKey(const ValueKey("localeOverrideDropdown"));
    expect(languageDropdown, findsOneWidget);

    await tester.ensureVisible(languageDropdown);
    await tester.pumpAndSettle();
    await tester.tap(languageDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Polish").last);
    await tester.pumpAndSettle();

    expect(
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.getString("localeOverride"),
        ),
        "pl");
    expect(localeService.localeOverrideCode, "pl");
  });

  testWidgets("settings screen ignores load completion after dispose",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localeService = _BlockingLocaleService();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(localeService: localeService),
      ),
    );
    await localeService.started;

    await tester.pumpWidget(const SizedBox.shrink());
    localeService.completeLoad();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _BlockingLocaleService extends AppLocaleService {
  final _started = Completer<void>();
  final _loadCompleter = Completer<void>();

  Future<void> get started => _started.future;

  @override
  Future<void> load() async {
    if (!_started.isCompleted) {
      _started.complete();
    }
    await _loadCompleter.future;
  }

  void completeLoad() {
    if (!_loadCompleter.isCompleted) {
      _loadCompleter.complete();
    }
  }
}
