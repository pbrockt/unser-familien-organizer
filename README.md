# 📅 Unser Familien-Organizer

**Der Familienplaner für die Nextcloud!**

Selbst-gehosteter **Familien-Organizer** — Kalender, Aufgaben und Einkaufsliste
für die ganze Familie. Alle Daten leben in deiner eigenen **Nextcloud** und
werden per **CalDAV** synchronisiert.

> Kein fremder Server. Kein Abo. Kein fremdes Konto.

## Download

Fertige Builds gibt es unter **[Releases](https://github.com/pbrockt/unser-familien-organizer/releases)**:

| Plattform | Datei |
|---|---|
| 📱 Android | `UnserFamilienOrganizer-<version>.apk` |
| 🪟 Windows | `UnserFamilienOrganizer-Setup-<version>.exe` (Installer) · `…-windows-<version>.zip` (portabel) |
| 🐧 Linux | `UnserFamilienOrganizer-<version>-amd64.deb` · `…-linux-<version>.tar.gz` (mit `install.sh`) |

Installationshinweise zu Desktop: siehe [installer/README.md](installer/README.md).

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
→ Artifact `UnserFamilienOrganizer-release`). Lokal:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # benötigt viel RAM
```

## Roadmap

Siehe [ToDo.md](ToDo.md) — der Phasenplan von Setup bis Release.
Kritischer Pfad: **Phase 2 – CalDAV Core**.

## Lizenz

[MIT](LICENSE) © 2026 Phillipp Brosch
