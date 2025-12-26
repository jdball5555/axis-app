import 'package:flutter/material.dart';

class AxisTheme {
  static const Color _teal = Color(0xFF00C897);

  // --- DARK THEME ---
  static final ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: Colors.black,
    cardColor: const Color(0xFF222222), // Dark Grey Tiles
    dividerColor: Colors.white10, // Faint borders
    primaryColor: _teal,

    colorScheme: const ColorScheme.dark(
      primary: _teal,
      secondary: _teal,
      surface: Colors.black,
      onSurface: Colors.white, // Main Text
      onSurfaceVariant: Colors.white54, // Subtitles
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 20,
      ),
    ),

    iconTheme: const IconThemeData(color: Colors.white54),

    // Switch styling
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith(
        (states) =>
            states.contains(MaterialState.selected) ? _teal : Colors.grey[400],
      ),
      trackColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.selected)
            ? _teal.withOpacity(0.4)
            : Colors.grey[800],
      ),
      trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
    ),
  );

  // --- LIGHT THEME ---
  static final ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: const Color(0xFFF2F4F7), // Soft Light Grey
    cardColor: Colors.white, // White Tiles
    dividerColor: Colors.black12, // Faint borders
    primaryColor: _teal,

    colorScheme: const ColorScheme.light(
      primary: _teal,
      secondary: _teal,
      surface: Color(0xFFF2F4F7),
      onSurface: Colors.black87, // Dark Grey Text
      onSurfaceVariant: Colors.black54, // Grey Subtitles
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 20,
      ),
    ),

    iconTheme: const IconThemeData(color: Colors.black45),

    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith(
        (states) =>
            states.contains(MaterialState.selected) ? _teal : Colors.white,
      ),
      trackColor: MaterialStateProperty.resolveWith(
        (states) => states.contains(MaterialState.selected)
            ? _teal.withOpacity(0.4)
            : Colors.grey[300],
      ),
      trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
    ),
  );
}
