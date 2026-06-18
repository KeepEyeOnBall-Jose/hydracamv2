import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";
import "package:hydracam/widgets/hydra_cam_app_bar.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("hides action menu during tiny startup layouts", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1, 80));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: HydraCamAppBar(
            title: "HydraCam - Slave Device",
            onBack: () {},
          ),
        ),
      ),
    );

    await tester.pump();

    final title = tester.widget<Text>(find.text("HydraCam - Slave Device"));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("uses dark squash chrome with accent navigation icons",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: HydraCamAppBar(
            title: "HydraCam",
            onBack: () {},
          ),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppTheme.appChrome);
    expect(appBar.foregroundColor, AppTheme.inverseText);
    expect(appBar.iconTheme?.color, AppTheme.accent);
    expect(appBar.actionsIconTheme?.color, AppTheme.accent);
  });

  testWidgets("popup menu preserves labels and uses squash accent icons",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: HydraCamAppBar(
            title: "HydraCam",
            onBack: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final expectedMenuItems = <(IconData, String)>[
      (Icons.info_outline, "Device Info"),
      (Icons.settings, "Settings"),
      (Icons.camera_alt, "Camera Selection"),
      (Icons.location_on, "Location Info"),
      (Icons.list_alt, "Logs"),
      (Icons.cloud_upload, "Uploader Info"),
      (Icons.perm_device_info, "App Version"),
      (Icons.login, "Login"),
    ];

    for (final (icon, label) in expectedMenuItems) {
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.text(label), findsOneWidget);

      final menuIcon = tester.widget<Icon>(find.byIcon(icon));
      expect(menuIcon.color, AppTheme.accent);
    }
  });
}
