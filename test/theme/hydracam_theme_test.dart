import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
}

void main() {
  test("readable text on both operational surfaces and appearances", () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final colors = theme.colorScheme;
      for (final background in [colors.surface, colors.surfaceContainerLow]) {
        expect(
            contrast(colors.onSurface, background), greaterThanOrEqualTo(4.5));
        expect(contrast(colors.onSurfaceVariant, background),
            greaterThanOrEqualTo(4.5));
      }
      expect(contrast(colors.onErrorContainer, colors.errorContainer),
          greaterThanOrEqualTo(4.5));
      expect(contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5));
    }
  });

  test("squash palette matches MediaTimeline contract", () {
    expect(AppTheme.squashBlack, const Color(0xFF000000));
    expect(AppTheme.squashWhite, const Color(0xFFFFFFFF));
    expect(AppTheme.squashYellow, const Color(0xFFFFC107));
    expect(AppTheme.squashRed, const Color(0xFFD32F2F));
  });

  test("light theme exposes operational squash roles", () {
    final theme = AppTheme.lightTheme;

    expect(theme.colorScheme.primary, AppTheme.accent);
    expect(theme.colorScheme.error, AppTheme.danger);
    expect(theme.scaffoldBackgroundColor, AppTheme.pageBackground);
    expect(theme.appBarTheme.backgroundColor, AppTheme.appChrome);
    expect(theme.appBarTheme.foregroundColor, AppTheme.squashWhite);
    expect(theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
        AppTheme.accent);
    expect(theme.elevatedButtonTheme.style?.foregroundColor?.resolve({}),
        AppTheme.textOnAccent);
  });
}
