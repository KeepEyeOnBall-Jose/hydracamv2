import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";
import "package:hydracam/l10n/app_localizations.dart";
import "package:hydracam/screens/settings_screen.dart";
import "package:hydracam/services/app_locale_service.dart";
import "package:shared_preferences/shared_preferences.dart";

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  AppLocaleService? localeService,
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(localeService: localeService),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets("settings fit compact width at 200% text, dark=$dark",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpSettingsScreen(tester, dark: dark, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip("Language"));
      await tester.pumpAndSettle();
      expect(find.text("Choose an app language or use your device setting."),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text("Close"));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("Storage location"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets("settings screen ignores locale update completion after dispose",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localeService = _BlockingLocaleUpdateService();

    await _pumpSettingsScreen(tester, localeService: localeService);

    final languageDropdown =
        find.byKey(const ValueKey("localeOverrideDropdown"));
    await tester.ensureVisible(languageDropdown);
    await tester.pumpAndSettle();
    await tester.tap(languageDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Polish").last);
    await localeService.setStarted;

    expect(localeService.requestedLocaleCode, "pl");

    await tester.pumpWidget(const SizedBox.shrink());
    localeService.completeSet();
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

class _BlockingLocaleUpdateService extends AppLocaleService {
  final _setStarted = Completer<void>();
  final _setCompleter = Completer<void>();

  String? requestedLocaleCode;

  Future<void> get setStarted => _setStarted.future;

  @override
  Future<void> load() async {}

  @override
  Future<void> setLocaleOverride(String? languageCode) async {
    requestedLocaleCode = languageCode;
    if (!_setStarted.isCompleted) {
      _setStarted.complete();
    }
    await _setCompleter.future;
  }

  void completeSet() {
    if (!_setCompleter.isCompleted) {
      _setCompleter.complete();
    }
  }
}
