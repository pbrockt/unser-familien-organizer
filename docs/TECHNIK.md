# 🔧 Technik & Entwicklung

Technische Details zu *Unser Familien-Organizer*. Für die Nutzer-Anleitung siehe
[ANLEITUNG.md](ANLEITUNG.md), für die Übersicht das [README](../README.md).

## Konzept

Die App ist reines **Frontend** – kein eigenes Backend. Alles liegt in der
Nextcloud des Nutzers und wird per **CalDAV** (RFC 4791) / **iCalendar**
(RFC 5545) synchronisiert.

| Bereich | Speicherung in Nextcloud |
|---|---|
| 📅 Kalender | `VEVENT` per CalDAV |
| ✔️ Aufgaben | `VTODO` per CalDAV (gleiche URL-Basis) |
| 🛒 Einkaufsliste | `VTODO`-Collection (`STATUS:COMPLETED` = abgehakt) |
| 👪 Familie | farbcodierte Personen + geteilte Kalender/Listen (Nextcloud-Sharing) |
| ⏰ Erinnerung | `VALARM` pro Termin |

## Tech-Stack

Flutter · Riverpod · GoRouter · enough_icalendar · table_calendar · sqflite ·
flutter_local_notifications · flutter_secure_storage · workmanager · home_widget ·
http · intl

## Architektur

```
lib/
├── core/
│   ├── caldav/   ← CalDAV-Client + iCal-Parser/-Builder + Repository (kritischer Kern)
│   ├── auth/     ← Nextcloud Login Flow v2 / Account
│   ├── sync/     ← Sync-Status, Offline-Queue, Konfliktlösung
│   ├── cache/    ← SQLite-Cache (Offline)
│   ├── background/← Hintergrund-Sync (workmanager)
│   ├── notifications/ ← lokale Benachrichtigungen
│   ├── update/   ← In-App-Update (GitHub Releases)
│   └── router/   ← GoRouter
├── features/
│   ├── home/     ← Startseite / Dashboard
│   ├── calendar/ ← VEVENT (Monats-/Tagesansicht, Presets)
│   ├── tasks/    ← VTODO
│   ├── shopping/ ← Einkaufsliste (VTODO-basiert)
│   ├── members/  ← Familienmitglieder / Sichtbarkeit
│   ├── weather/  ← Wetter (Open-Meteo)
│   └── settings/ ← Einstellungen, Erinnerungen, Update
└── shared/       ← Theme, Widgets, Utils
```

## Build

Releases (Android-APK, Windows-Installer/ZIP, Linux-.deb/tar.gz) werden bei einem
Versions-Tag von **GitHub Actions** gebaut und veröffentlicht.

Lokal:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Die CI bricht bei Info-Level-Lints ab (`flutter analyze` muss sauber sein).

## Veröffentlichen

```bash
# Version in pubspec.yaml erhöhen, dann:
git tag 0.54.1
git push origin main
git push origin 0.54.1   # löst Build + Release aus
```

## Roadmap

Siehe [ToDo.md](../ToDo.md).

## Lizenz

[MIT](../LICENSE) © 2026 pbrockt
