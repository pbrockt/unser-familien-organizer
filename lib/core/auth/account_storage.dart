import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nextcloud_account.dart';

/// Persistiert das [NextcloudAccount] verschlüsselt (Android Keystore via
/// flutter_secure_storage). Speichert ausschließlich das App-Passwort.
class AccountStorage {
  AccountStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'nextcloud_account';

  Future<NextcloudAccount?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return NextcloudAccount.decode(raw);
    } catch (_) {
      // Beschädigter Eintrag → wegwerfen, damit die App nicht hängen bleibt.
      await clear();
      return null;
    }
  }

  Future<void> write(NextcloudAccount account) async {
    await _storage.write(key: _key, value: account.encode());
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
