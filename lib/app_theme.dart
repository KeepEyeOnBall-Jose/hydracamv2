import 'package:flutter/material.dart';

class AppTheme {

  // Define main
  /*
  static const Color primaryColor = Color(0xFFFF4f6c); // Color(0xFF81FFBF); // Light green
  static const Color secondaryColor = Color(0xFFF5F5F5); // Light gray for backgrounds
  static const Color accentColor = Color(0xFF790026);    //Color(0xFF00796B); // Teal for accents
  static const Color lightAccentColor = Color(0xFFc74a71);
  static const Color buttonTextColor = Colors.black; // Black for button text
  static const Color disabledButtonColor = Color(0xFF949494); // Grey
  */
  // Define main colors
  static const Color primaryColor = Color(0xFFFFC107); // Amarillo principal
  static const Color secondaryColor = Color(0xFFF5F5F5); // Gris claro para fondos (monocromático, sin cambios)
  static const Color accentColor = Color(0xFFFFA000); // Amarillo más oscuro para acentos
  static const Color lightAccentColor = Color(0xFFFFD54F); // Amarillo más claro para acentos suaves
  static const Color buttonTextColor = Colors.black; // Negro para texto de botones (monocromático, sin cambios)
  static const Color disabledButtonColor = Color(0xFF949494); // Gris para botones deshabilitados (monocromático, sin cambios)


  // Define text styles
  static const TextStyle headline1 = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  static const TextStyle bodyText1 = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: Colors.black87,
  );

  // Define ThemeData
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: secondaryColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
      iconTheme: IconThemeData(
        color: Colors.black, // AppBar icons color
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: headline1,
      bodyLarge: bodyText1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor, // Button background color
        foregroundColor: buttonTextColor, // Button text color (black by default)
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    ),
    buttonTheme: const ButtonThemeData(
      buttonColor: primaryColor, // Default button color
      disabledColor: disabledButtonColor, // Button color when disabled
      textTheme: ButtonTextTheme.primary, // Ensure button text respects text color
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return primaryColor; // Active state thumb color
        }
        return disabledButtonColor; // Inactive state thumb color
      }),
      trackColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return accentColor.withOpacity(0.5); // Active state track color
        }
        return secondaryColor; // Inactive state track color
      }),
    ),
  );
}



// Use example

/*

Container(
  color: AppTheme.secondaryColor, // Background color
  child: Text(
    'Hello World',
    style: AppTheme.headline1, // Predefined text style
  ),
);

*/