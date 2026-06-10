/// Orchestriert den Abgleich zwischen Nextcloud (CalDAV) und dem lokalen
/// SQLite-Cache.
///
/// Phase 2: Delta-Sync + Offline-Fähigkeit.
///
/// Ablauf:
///  - Online  → pro Collection CTag prüfen; bei Änderung ETags vergleichen
///              und nur geänderte Objekte nachladen (Delta-Sync).
///  - Offline → lokale Änderungen in eine SQLite-Queue schreiben.
///  - Wieder online → Queue abarbeiten, Konflikte per ETag auflösen.
///
/// Im Hintergrund angestoßen über `workmanager` (periodischer Sync).
class SyncEngine {
  const SyncEngine();

  // TODO(phase2): syncAll / enqueueChange / drainQueue / resolveConflicts
}
