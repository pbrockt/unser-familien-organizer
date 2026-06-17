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

/// Status + Diagnose-Infos (für das Fehler-Popup auf der Startseite).
class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastError,
    this.lastSuccessAt,
    this.debugInfo,
    this.lastAttemptAt,
  });

  final SyncStatus status;

  /// Fehlermeldung des letzten fehlgeschlagenen Syncs (sonst null).
  final String? lastError;

  /// Zeitpunkt des letzten erfolgreichen Syncs (sonst null).
  final DateTime? lastSuccessAt;

  /// Zeitpunkt des letzten Sync-Versuchs (egal ob erfolgreich).
  final DateTime? lastAttemptAt;

  /// Debug-Bericht des letzten Syncs (Quelle, Collections + Anzahl, Fehler).
  final String? debugInfo;

  SyncState copyWith({
    SyncStatus? status,
    String? lastError,
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    String? debugInfo,
    bool clearError = false,
  }) =>
      SyncState(
        status: status ?? this.status,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        debugInfo: debugInfo ?? this.debugInfo,
      );
}

class SyncStatusController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  void setSyncing() => state = state.copyWith(
        status: SyncStatus.syncing,
        lastAttemptAt: DateTime.now(),
      );

  void setOnline() => state = state.copyWith(
        status: SyncStatus.online,
        lastSuccessAt: DateTime.now(),
        clearError: true,
      );

  void setOffline(String error) =>
      state = state.copyWith(status: SyncStatus.offline, lastError: error);

  void setDebug(String info) => state = state.copyWith(debugInfo: info);
}

final syncStatusProvider =
    NotifierProvider<SyncStatusController, SyncState>(SyncStatusController.new);
