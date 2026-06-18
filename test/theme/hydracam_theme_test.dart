import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";

void main() {
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
