import 'package:material_ui/material_ui.dart';

final lightTheme = ValueNotifier<bool>(false);
Color get background =>
    lightTheme.value ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
Color get surface =>
    lightTheme.value ? const Color(0xFFF8F8F8) : const Color(0xFF101010);
Color get panel => surface;
Color get accent =>
    lightTheme.value ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
Color get cyan => accent;
Color get muted =>
    lightTheme.value ? const Color(0xFF555555) : const Color(0xFFAAAAAA);
Color get lineColor =>
    lightTheme.value ? const Color(0xFFCCCCCC) : const Color(0xFF333333);
Color get success => accent;
ThemeData studioTheme() {
  final brightness = lightTheme.value ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'StudioSans',
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: background,
      secondary: accent,
      onSecondary: background,
      error: accent,
      onError: background,
      surface: surface,
      onSurface: accent,
    ),
    dividerColor: lineColor,
    textTheme: (lightTheme.value ? ThemeData.light() : ThemeData.dark())
        .textTheme
        .apply(
          fontFamily: 'StudioSans',
          bodyColor: accent,
          displayColor: accent,
        ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: lineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: lineColor),
      ),
    ),
  );
}

const mono = TextStyle(fontFamily: 'StudioMono', fontSize: 15, height: 1.7);
String shownWord(String word) => word.isEmpty ? 'ε' : word;
