# 📋 FamilyPlanner — ToDo / Roadmap

Selbst-gehosteter Familienplaner (Kalender + Aufgaben + Einkaufsliste).
Alle Daten leben in **Nextcloud** via **CalDAV**. Kein eigener Server, kein Abo.

Stand: Juni 2026 · App: Flutter (Android, später Web)

---

## ✅ Phase 1 — Projektsetup & Gerüst
- [x] Flutter-Toolchain (SDK 3.44, Dart 3.12, Android SDK 36) eingerichtet
- [x] Projekt `flutter create` (org `com.pbrockt`, Plattformen android+web)
- [x] Architektur-Ordnerstruktur (`core/`, `features/`, `shared/`)
- [x] Dependencies: riverpod, go_router, enough_icalendar, table_calendar,
      sqflite, flutter_local_notifications, flutter_secure_storage,
      shared_preferences, workmanager, http, intl, uuid
- [x] Lauffähiges Grundgerüst: Bottom-Nav (Kalender/Aufgaben/Einkauf/Familie)
- [x] Theme (Material 3) + Familienfarben-Palette
- [x] `flutter analyze` sauber, Smoke-Test grün
- [x] GitHub Actions: Release-APK-Build + Signierung (wie Tagebuch-App)
- [ ] Erster grüner CI-Lauf, APK aus Artifacts geladen & installiert

## ⚠️ Phase 2 — CalDAV Core (KRITISCHER PFAD)
> Alles hängt davon ab. Erst danach starten die UI-Phasen.
- [ ] `CalDavClient`: PROPFIND (Collections entdecken)
- [ ] `CalDavClient`: REPORT (Objekte je Collection / Zeitraum)
- [ ] `CalDavClient`: GET / PUT (mit If-Match ETag) / DELETE
- [ ] CTag-Check (billige Änderungserkennung pro Collection)
- [ ] `IcalParser`: VEVENT + VTODO ↔ App-Modelle (enough_icalendar)
- [ ] SQLite-Cache (sqflite) für Offline-Lesen
- [ ] `SyncEngine`: Delta-Sync (CTag/ETag) + Offline-Queue + Konfliktlösung
- [ ] Self-Signed-Zertifikat-Support (Heimserver/Unraid)

## 🔐 Phase 3 — Nextcloud-Verbindung & Onboarding
- [ ] Nextcloud Login Flow v2 (App-Passwort, nie Hauptpasswort)
- [ ] Credentials in `flutter_secure_storage` (Android Keystore)
- [ ] Onboarding-Flow + Verbindungstest
- [ ] Navigation/Design-Feinschliff

## 📅 Phase 4 — Kalender-UI
- [ ] `table_calendar`: Monat / Woche / Agenda
- [ ] Termine farbcodiert pro Person
- [ ] Termin anlegen/bearbeiten/löschen (VEVENT)
- [ ] Serientermine (RRULE), Ganztags-Events

## ✔️ Phase 5 — Aufgaben-UI
- [ ] Aufgabenlisten anzeigen
- [ ] Abhaken (STATUS:COMPLETED)
- [ ] Unteraufgaben (RELATED-TO), Priorität, Fälligkeit

## 🛒 Phase 6 — Einkaufsliste
- [ ] VTODO-Collection als Einkaufsliste (Name=SUMMARY, Menge=DESCRIPTION)
- [ ] Abhaken + Kategorien (CATEGORIES)
- [ ] Mehrere Listen (z.B. einkauf-rewe, einkauf-baumarkt)

## 👪 Phase 7 — Familiengruppen
- [ ] Mitglieder + Farbzuordnung
- [ ] Geteilte Kalender/Listen auswählen
- [ ] (Optional) Einladungs-/Verknüpfungslogik

## 🔔 Phase 8 — Benachrichtigungen
- [ ] VALARM → lokale Notifications (flutter_local_notifications)
- [ ] Hintergrund-Sync (workmanager)

## 🔒 Phase 9 — Sicherheit
- [ ] Keystore/Secrets-Handling final
- [ ] Self-Signed-Cert UX (Vertrauen bestätigen)

## 🚀 Phase 10 — Release
- [ ] Testing
- [ ] F-Droid / Play Store / direkter APK-Download

---

## 🔗 Nextcloud-URLs (Referenz)
```
Basis DAV:   https://cloud.example.com/remote.php/dav
Kalender:    https://cloud.example.com/remote.php/dav/calendars/{user}/
Tasks:       https://cloud.example.com/remote.php/dav/calendars/{user}/{liste}/
Well-Known:  https://cloud.example.com/.well-known/caldav
```

## 📚 Wichtige Specs
- CalDAV: RFC 4791 · iCalendar: RFC 5545
- Nextcloud Login Flow v2 (developer_manual/client_apis/LoginFlow)
