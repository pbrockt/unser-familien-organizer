import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../caldav/caldav_client.dart';
import '../caldav/http_caldav_client.dart';
import 'account_storage.dart';
import 'nextcloud_account.dart';

/// Verschlüsselter Konto-Speicher.
final accountStorageProvider = Provider<AccountStorage>((ref) {
  return AccountStorage();
});

/// CalDAV-Client (Implementierung gegen Nextcloud).
final caldavClientProvider = Provider<CalDavClient>((ref) {
  return const HttpCalDavClient();
});

/// Aktuell verbundenes Nextcloud-Konto (oder `null`, wenn nicht verbunden).
/// Lädt beim Start aus dem sicheren Speicher.
final accountProvider =
    AsyncNotifierProvider<AccountNotifier, NextcloudAccount?>(
  AccountNotifier.new,
);

class AccountNotifier extends AsyncNotifier<NextcloudAccount?> {
  AccountStorage get _storage => ref.read(accountStorageProvider);

  @override
  Future<NextcloudAccount?> build() => _storage.read();

  /// Konto speichern und als aktiv setzen (nach erfolgreichem Verbindungstest).
  Future<void> save(NextcloudAccount account) async {
    final normalized = account.normalized();
    await _storage.write(normalized);
    state = AsyncData(normalized);
  }

  /// Verbindung trennen und Zugangsdaten löschen.
  Future<void> disconnect() async {
    await _storage.clear();
    state = const AsyncData(null);
  }
}

/// Bequemer Lese-Provider: Liste der entdeckten Collections des Kontos.
/// Wird vom Familie-Tab genutzt, um Kalender/Listen anzuzeigen.
final collectionsProvider = FutureProvider.autoDispose((ref) async {
  final account = await ref.watch(accountProvider.future);
  if (account == null) return const <CalDavCollection>[];
  final client = ref.watch(caldavClientProvider);
  return client.listCollections(account);
});
