import 'package:flutter/material.dart';
import 'theme/palette.dart';
import 'ui/screens/camera_screen.dart';
import 'ui/screens/history_screen.dart';

class FoodSpyApp extends StatelessWidget {
  const FoodSpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.accent,
        primary: Palette.accent,
        secondary: Palette.lilac,
        surface: Colors.white,
      ),
      useMaterial3: true,
      fontFamily: 'SF Pro',make gitignore
      scaffoldBackgroundColor: Palette.blush,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Palette.peach,
        contentTextStyle: TextStyle(color: Palette.deepText),
      ),
    );

    return MaterialApp(
      title: 'FoodSpy',
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
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Palette.accent,
          unselectedItemColor: Palette.deepText.withValues(alpha: 0.5),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    CameraScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Capture',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
