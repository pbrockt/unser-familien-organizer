// Smoke-Test: App startet und zeigt die Bottom-Navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:family_planner/app.dart';
import 'package:family_planner/core/auth/account_providers.dart';
import 'package:family_planner/core/auth/account_storage.dart';
import 'package:family_planner/core/auth/nextcloud_account.dart';

/// Fake-Storage ohne Plattform-Plugin: gibt "nicht verbunden" zurück.
class _FakeAccountStorage extends AccountStorage {
  @override
  Future<NextcloudAccount?> read() async => null;
  @override
  Future<void> write(NextcloudAccount account) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE', null));

  testWidgets('App startet und zeigt die Navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStorageProvider.overrideWithValue(_FakeAccountStorage()),
        ],
        child: const FamilyPlannerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Aufgaben'), findsOneWidget);
    expect(find.text('Einkauf'), findsOneWidget);
    expect(find.text('Neu'), findsOneWidget);
    // 'Familie' ist kein Tab mehr (jetzt unter Einstellungen).
    expect(find.text('Familie'), findsNothing);
  });
}
