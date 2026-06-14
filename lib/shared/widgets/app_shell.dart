import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Grundgerüst mit persistenter Bottom-Navigation. Hält die fünf
/// Hauptbereiche (Start, Kalender, Aufgaben, Einkauf, Familie) als Tabs.
///
/// Der Android-Zurück-Knopf navigiert durch die zuvor besuchten Tabs, statt
/// die App sofort zu schließen (eigene Tab-Historie).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final List<int> _history = [];

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _handleBack() {
    if (_history.length <= 1) return;
    _history.removeLast();
    final prev = _history.last;
    widget.navigationShell.goBranch(prev, initialLocation: false);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Jeden Tab-Wechsel (auch via context.go von der Startseite) in der
    // Historie mitführen, damit „Zurück" Schritt für Schritt zurückgeht.
    final idx = widget.navigationShell.currentIndex;
    if (_history.isEmpty || _history.last != idx) {
      _history.add(idx);
    }
    return PopScope(
      canPop: _history.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Kalender',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Aufgaben',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Einkauf',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Familie',
          ),
        ],
      ),
      ),
    );
  }
}
