import 'package:flutter/material.dart';
import 'theme/palette.dart';
import 'ui/screens/camera_screen.dart';

class PlateDepthApp extends StatelessWidget {
  const PlateDepthApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.accent,
        primary: Palette.accent,
        secondary: Palette.lilac,
        background: Palette.blush,
        surface: Colors.white,
      ),
      useMaterial3: true,
      fontFamily: 'SF Pro',
      scaffoldBackgroundColor: Palette.blush,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Palette.peach,
        contentTextStyle: TextStyle(color: Palette.deepText),
      ),
    );

    return MaterialApp(
      title: 'PlateDepth',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Palette.sky,
          foregroundColor: Palette.deepText,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Palette.accent,
          foregroundColor: Colors.white,
        ),
      ),
      home: const CameraScreen(),
    );
  }
}
