import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/account_providers.dart';
import '../../core/platform/platform_support.dart';
import '../../features/calendar/event_editor_sheet.dart';
import '../../features/tasks/task_editor_sheet.dart';
import '../../features/tasks/task_providers.dart';
import '../../features/update/update_prompt.dart';

/// Grundgerüst mit persistenter Bottom-Navigation: Start, Kalender, Aufgaben,
/// Einkauf und ein „+", über das man direkt einen Termin oder eine Aufgabe
/// anlegt. Die Familie-/Verbindungs-Verwaltung sitzt in den Einstellungen.
///
/// Der Android-Zurück-Knopf navigiert durch die zuvor besuchten Tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final List<int> _history = [];
  bool _updateChecked = false;

  /// Index der „+"-Schaltfläche (keine echte Seite, sondern eine Aktion).
  static const int _plusIndex = 4;

  @override
  void initState() {
    super.initState();
    // Beim Start einmalig auf eine neue Version prüfen. Hier (im Navigator)
    // gibt es einen gültigen Context für den Update-Dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_updateChecked || !mounted) return;
      _updateChecked = true;
      if (!isAndroid) return;
      runUpdateCheck(context, ref, silentIfNone: true);
    });
  }

  void _onDestination(int index) {
    if (index == _plusIndex) {
      _showCreateMenu();
      return;
    }
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

  Future<void> _showCreateMenu() async {
    final account = ref.read(accountProvider).value;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erst mit Nextcloud verbinden '
            '(Einstellungen → Familie).'),
      ));
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Neuer Termin'),
              onTap: () => Navigator.pop(ctx, 'event'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Neue Aufgabe'),
              onTap: () => Navigator.pop(ctx, 'task'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'event') {
      await showEventEditor(context);
    } else {
      final lists = ref.read(tasksControllerProvider).value ?? const [];
      if (lists.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Keine Aufgabenliste vorhanden. Lege zuerst eine an '
                '(Einstellungen → Familie).'),
          ));
        }
        return;
      }
      await showTaskEditor(context, lists: lists);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Jeden Tab-Wechsel in der Historie mitführen, damit „Zurück" Schritt für
    // Schritt zurückgeht.
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
          onDestinationSelected: _onDestination,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Start',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Kalender',
            ),
            const NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle),
              label: 'Aufgaben',
            ),
            const NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined),
              selectedIcon: Icon(Icons.shopping_cart),
              label: 'Einkauf',
            ),
            NavigationDestination(
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
              label: 'Neu',
            ),
          ],
        ),
      ),
    );
  }
}
