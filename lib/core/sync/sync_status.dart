import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aktueller Verbindungs-/Sync-Zustand zur Nextcloud. Wird am Avatar auf der
/// Startseite als kleiner Statuspunkt angezeigt, damit man direkt sieht, ob
/// gerade online/offline gearbeitet wird.
enum SyncStatus {
  /// Noch kein Sync versucht (z. B. direkt nach App-Start).
  idle,

  /// Synchronisation läuft gerade.
  syncing,

  /// Letzter Sync erfolgreich / Server erreichbar.
  online,

  /// Server nicht erreichbar – es wird offline (aus dem Cache) gearbeitet.
  offline,
}

class SyncStatusController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.idle;

  void set(SyncStatus status) => state = status;
}

final syncStatusProvider =
    NotifierProvider<SyncStatusController, SyncStatus>(SyncStatusController.new);
