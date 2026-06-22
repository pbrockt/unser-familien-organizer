import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/auth/account_providers.dart';
import '../../core/platform/platform_support.dart';
import '../../features/calendar/event_editor_sheet.dart';
import '../../features/calendar/event_providers.dart';
import '../../features/calendar/quick_entry_sheet.dart';
import '../../features/study/study_planner_sheet.dart';
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
  StreamSubscription<Uri?>? _widgetSub;

  /// Index der „+"-Schaltfläche (keine echte Seite, sondern eine Aktion).
  static const int _plusIndex = 4;

  @override
  void initState() {
    super.initState();
    // Beim Start einmalig auf eine neue Version prüfen. Hier (im Navigator)
    // gibt es einen gültigen Context für den Update-Dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_updateChecked && isAndroid) {
        _updateChecked = true;
        runUpdateCheck(context, ref, silentIfNone: true);
      }
      _handleInitialWidgetLaunch();
    });
    // Klicks aus Widgets, während die App schon läuft.
    if (isAndroid) {
      _widgetSub = HomeWidget.widgetClicked.listen((uri) {
        if (mounted) _handleWidgetUri(uri);
      });
    }
  }

  @override
  void dispose() {
    _widgetSub?.cancel();
    super.dispose();
  }

  /// Wurde die App über ein Widget gestartet? Dann passend reagieren.
  Future<void> _handleInitialWidgetLaunch() async {
    if (!isAndroid) return;
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (mounted) _handleWidgetUri(uri);
    } catch (_) {}
  }

  /// `familyplanner://newevent` → Termin-Editor; sonst passenden Tab öffnen.
  void _handleWidgetUri(Uri? uri) {
    if (uri == null || !mounted) return;
    final target = uri.host.isNotEmpty
        ? uri.host
        : uri.path.replaceAll('/', '');
    switch (target) {
      case 'newevent':
        _openNewEvent();
        break;
      case 'calendar':
        widget.navigationShell.goBranch(1, initialLocation: false);
        break;
      case 'tasks':
        widget.navigationShell.goBranch(2, initialLocation: false);
        break;
      case 'shopping':
        widget.navigationShell.goBranch(3, initialLocation: false);
        break;
      case 'home':
        widget.navigationShell.goBranch(0, initialLocation: false);
        break;
      case 'sync':
        ref.invalidate(eventsControllerProvider);
        ref.invalidate(tasksControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synchronisiere mit der Nextcloud…')),
        );
        break;
    }
  }

  Future<void> _openNewEvent() async {
    final account = ref.read(accountProvider).value;
    if (account == null || !mounted) return;
    await showEventEditor(context, initialDay: DateTime.now());
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erst mit Nextcloud verbinden '
            '(Einstellungen → Familie).',
          ),
        ),
      );
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
              leading: const Icon(Icons.bolt),
              title: const Text('Schnell-Eingabe'),
              subtitle: const Text('z. B. „Zahnarzt morgen 15 Uhr"'),
              onTap: () => Navigator.pop(ctx, 'quick'),
            ),
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
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Schularbeit (Lernplan)'),
              subtitle: const Text(
                'Arbeit eintragen, Lern-Tage automatisch planen',
              ),
              onTap: () => Navigator.pop(ctx, 'study'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'quick') {
      await showQuickEntrySheet(context, ref);
    } else if (choice == 'study') {
      await showStudyPlannerSheet(context);
    } else if (choice == 'event') {
      // Im Kalender-Tab den dort gewählten Tag vorbelegen (sonst heute).
      final onCalendar = widget.navigationShell.currentIndex == 1;
      final day = onCalendar ? ref.read(calendarSelectedDayProvider) : null;
      await showEventEditor(context, initialDay: day);
    } else {
      final lists = ref.read(tasksControllerProvider).value ?? const [];
      if (lists.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Keine Aufgabenliste vorhanden. Lege zuerst eine an '
                '(Einstellungen → Familie).',
              ),
            ),
          );
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Breite Fenster (Desktop/Tablet, Material „expanded"): seitliche
          // NavigationRail statt Bottom-Bar; Inhalt mittig auf angenehme Breite
          // begrenzen.
          if (constraints.maxWidth >= 840) {
            return Scaffold(
              body: Row(
                children: [
                  _buildRail(context),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: widget.navigationShell,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return Scaffold(
            body: widget.navigationShell,
            bottomNavigationBar: _buildBottomBar(context),
          );
        },
      ),
    );
  }

  /// Bottom-Navigation für schmale Fenster (Handy).
  Widget _buildBottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
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
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add, color: scheme.onPrimary),
          ),
          label: 'Neu',
        ),
      ],
    );
  }

  /// Seiten-Navigation für breite Fenster (Desktop/Tablet). „Neu" sitzt als
  /// FAB oben; die vier Bereiche darunter.
  Widget _buildRail(BuildContext context) {
    return NavigationRail(
      selectedIndex: widget.navigationShell.currentIndex,
      onDestinationSelected: _onDestination,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: FloatingActionButton(
          tooltip: 'Neu',
          elevation: 1,
          onPressed: () => _onDestination(_plusIndex),
          child: const Icon(Icons.add),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Start'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: Text('Kalender'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.check_circle_outline),
          selectedIcon: Icon(Icons.check_circle),
          label: Text('Aufgaben'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.shopping_cart_outlined),
          selectedIcon: Icon(Icons.shopping_cart),
          label: Text('Einkauf'),
        ),
      ],
    );
  }
}
