// Smoke-Test: App startet und zeigt die Bottom-Navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_planner/app.dart';

void main() {
  testWidgets('App startet und zeigt die vier Navigations-Tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FamilyPlannerApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Aufgaben'), findsOneWidget);
    expect(find.text('Einkauf'), findsOneWidget);
    expect(find.text('Familie'), findsOneWidget);
  });
}
