import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/calendar_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/school/school_screen.dart';
import '../../features/shopping/shopping_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Globaler Router der App. Nutzt eine [StatefulShellRoute] für die
/// persistente Bottom-Navigation zwischen den vier Hauptbereichen.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shopping',
                builder: (context, state) => const ShoppingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/school',
                builder: (context, state) => const SchoolScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Seite nicht gefunden: ${state.uri}')),
    ),
  );
});
