import "package:flutter/material.dart";

// ignore: avoid_classes_with_only_static_members
class AppTheme {
  static const Color squashBlack = Color(0xFF000000);
  static const Color squashWhite = Color(0xFFFFFFFF);
  static const Color squashYellow = Color(0xFFFFC107);
  static const Color squashRed = Color(0xFFD32F2F);

  static const Color neutral900 = Color(0xFF212121);
  static const Color neutral700 = Color(0xFF595959);
  static const Color neutral600 = Color(0xFF757575);
  static const Color neutral500 = Color(0xFF9E9E9E);
  static const Color neutral400 = Color(0xFFBDBDBD);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral200 = Color(0xFFEEEEEE);
  static const Color neutral100 = Color(0xFFF5F5F5);

  static const Color pageBackground = neutral100;
  static const Color surface = squashWhite;
  static const Color surfaceMuted = neutral100;
  static const Color surfaceAlt = neutral200;
  static const Color appChrome = squashBlack;
  static const Color cameraCanvas = squashBlack;
  static const Color previewOverlay = Color(0x3DFFFFFF);

  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral700;
  static const Color textTertiary = neutral700;
  static const Color textOnAccent = squashBlack;
  static const Color inverseText = squashWhite;
  static const Color inverseTextMuted = Color(0xB3FFFFFF);

  static const Color border = neutral300;
  static const Color borderStrong = neutral400;
  static const Color accent = squashYellow;
  static const Color accentSurface = Color(0x1FFFC107);
  static const Color danger = squashRed;
  static const Color dangerSurface = Color(0x1FD32F2F);
  static const Color critical = danger;

  static const Color disabledButtonColor = neutral500;
  static const Color disabledSurface = neutral200;

  static const Color primaryColor = accent;
  static const Color accentColor = accent;
  static const Color lightAccentColor = accentSurface;

  static const TextStyle headline1 = TextStyle(
    fontFamily: "Montserrat",
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static const TextStyle bodyText1 = TextStyle(
    fontFamily: "Montserrat",
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: "Montserrat",
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(8));

  static ButtonStyle primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: textOnAccent,
      disabledBackgroundColor: disabledSurface,
      disabledForegroundColor: textSecondary,
      textStyle: const TextStyle(
        fontFamily: "Montserrat",
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      shape: const RoundedRectangleBorder(borderRadius: smallRadius),
      minimumSize: const Size(0, 44),
    );
  }

  static ButtonStyle dangerButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: danger,
      foregroundColor: inverseText,
      disabledBackgroundColor: disabledSurface,
      disabledForegroundColor: textSecondary,
      textStyle: const TextStyle(
        fontFamily: "Montserrat",
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      shape: const RoundedRectangleBorder(borderRadius: smallRadius),
      minimumSize: const Size(0, 44),
    );
  }

  static final ThemeData lightTheme = _theme(Brightness.light);
  static final ThemeData darkTheme = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? neutral900 : AppTheme.surface;
    final muted = dark ? const Color(0xFF181818) : surfaceMuted;
    final foreground = dark ? neutral100 : textPrimary;
    final secondary = dark ? neutral400 : textSecondary;
    final outline = dark ? neutral600 : border;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: accent,
      scaffoldBackgroundColor: dark ? const Color(0xFF121212) : pageBackground,
      fontFamily: "Montserrat",
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        primary: accent,
        onPrimary: textOnAccent,
        secondary: accent,
        onSecondary: textOnAccent,
        error: dark ? const Color(0xFFFF8A80) : danger,
        onError: inverseText,
        surface: surface,
        onSurface: foreground,
        onSurfaceVariant: secondary,
        surfaceContainerLow: muted,
        surfaceContainerHighest: dark ? neutral900 : surfaceAlt,
        outline: secondary,
        outlineVariant: outline,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: appChrome,
        foregroundColor: squashWhite,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: squashWhite,
        ),
        iconTheme: IconThemeData(color: accent),
        actionsIconTheme: IconThemeData(color: accent),
      ),
      textTheme: TextTheme(
        displayLarge: headline1.copyWith(color: foreground),
        headlineSmall: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        titleMedium: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        bodyLarge: bodyText1.copyWith(color: foreground),
        bodyMedium: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: foreground,
        ),
        bodySmall: caption.copyWith(color: secondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle()),
      filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: smallRadius),
          minimumSize: const Size(0, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(borderRadius: smallRadius),
        ),
      ),
      buttonTheme: const ButtonThemeData(
        buttonColor: accent,
        disabledColor: disabledButtonColor,
        textTheme: ButtonTextTheme.primary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: smallRadius,
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: surface,
        titleTextStyle: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        contentTextStyle: TextStyle(
          fontFamily: "Montserrat",
          fontSize: 14,
          color: foreground,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: smallRadius,
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: smallRadius,
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: smallRadius,
          borderSide: BorderSide(color: foreground, width: 2),
        ),
        labelStyle: TextStyle(color: secondary),
        hintStyle: TextStyle(color: secondary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: surface,
        textStyle: TextStyle(color: foreground),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: appChrome,
        contentTextStyle: TextStyle(color: inverseText),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textOnAccent;
          }
          return disabledButtonColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent;
          }
          return border;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: border,
        linearTrackColor: border,
      ),
    );
  }
}
