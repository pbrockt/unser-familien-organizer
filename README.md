# 📅 FamilyPlanner

Selbst-gehosteter **Familienplaner** im Planily/FamilyWall-Stil — Kalender,
Aufgaben und Einkaufsliste für die ganze Familie. Alle Daten leben in deiner
eigenen **Nextcloud** und werden per **CalDAV** synchronisiert.

> Kein fremder Server. Kein Abo. Kein fremdes Konto.

## Konzept

| Bereich | Speicherung in Nextcloud |
|---|---|
| 📅 Kalender | `VEVENT` per CalDAV (RFC 4791) |
| ✔️ Aufgaben | `VTODO` per CalDAV (gleiche URL-Basis) |
| 🛒 Einkaufsliste | spezielle `VTODO`-Collection (`STATUS:COMPLETED` = abgehakt) |
| 👪 Familie | farbcodierte Personen + geteilte Kalender/Listen |

Die App ist reines **Frontend** — kein eigenes Backend nötig.

## Tech-Stack

Flutter · Riverpod · GoRouter · enough_icalendar · table_calendar · sqflite ·
flutter_local_notifications · flutter_secure_storage · workmanager

## Architektur

```
lib/
├── core/
│   ├── caldav/   ← CalDAV Client + iCal Parser + Sync Engine (kritischer Kern)
│   ├── auth/     ← Nextcloud Login Flow v2 / Account
│   ├── sync/     ← Offline-Queue, Konfliktlösung
│   ├── db/       ← SQLite-Cache
│   └── router/   ← GoRouter
├── features/
│   ├── calendar/ ← VEVENT
│   ├── tasks/    ← VTODO
│   ├── shopping/ ← Einkaufsliste (VTODO-basiert)
│   └── family/   ← Familiengruppen / Personen
└── shared/       ← Theme, Widgets, Utils
```

## Build

Das Release-APK wird von **GitHub Actions** gebaut (Tab *Actions* → *Build APK*
→ Artifact `FamilyPlanner-release`). Lokal:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # benötigt viel RAM
```

## Roadmap

Siehe [ToDo.md](ToDo.md) — der Phasenplan von Setup bis Release.
Kritischer Pfad: **Phase 2 – CalDAV Core**.
