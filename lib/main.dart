import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/library_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/stats_screen.dart';

void main() {
  runApp(const ProviderScope(child: MangaApp()));
}

class MangaApp extends StatelessWidget {
  const MangaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manga Bookmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          background:    Color(0xFFFFFFFF),
          surface:       Color(0xFFF5F5F5),
          surfaceVariant:Color(0xFFEEEEEE),
          primary:       Color(0xFF111111),
          onPrimary:     Color(0xFFFFFFFF),
          secondary:     Color(0xFF555555),
          onSecondary:   Color(0xFFFFFFFF),
          onBackground:  Color(0xFF111111),
          onSurface:     Color(0xFF111111),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        cardColor: const Color(0xFFF5F5F5),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          indicatorColor:  Color(0xFFEEEEEE),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF111111)),
          titleTextStyle: TextStyle(color: Color(0xFF111111), fontSize: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: const Color(0xFFF0F0F0),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Color(0xFF999999)),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _tapNotifiers = [ValueNotifier(0), ValueNotifier(0), ValueNotifier(0)];

  late final List<Widget> _screens = [
    LibraryScreen(tapNotifier: _tapNotifiers[0]),
    const ChatScreen(),
    StatsScreen(tapNotifier: _tapNotifiers[2]),
  ];

  @override
  void dispose() {
    for (final n in _tapNotifiers) n.dispose();
    super.dispose();
  }

  static const _icons = [
    Icons.menu_book_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.bar_chart_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final navHeight = 62.0;
    final navBottom = (bottomPad > 0 ? bottomPad / 2 : 8.0);

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),
          // Floating pill nav bar
          Positioned(
            left: 0,
            right: 0,
            bottom: navBottom,
            child: Center(
              child: Container(
                height: navHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_icons.length, (i) {
                    final selected = _index == i;
                    return GestureDetector(
                      onTap: () {
                    if (_index == i) {
                      _tapNotifiers[i].value++;
                    } else {
                      setState(() => _index = i);
                    }
                  },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: selected ? 64 : 52,
                        height: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFF3A3A3A) : Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Icon(_icons[i], color: Colors.white, size: 24),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
