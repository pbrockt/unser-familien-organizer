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
- [x] Erster grüner CI-Lauf — APK gebaut & als Artifact hochgeladen (~21 MB)
- [ ] APK aufs Handy laden & installieren (Actions → Artifact `FamilyPlanner-release`)

## ⚠️ Phase 2 — CalDAV Core (KRITISCHER PFAD)
> Alles hängt davon ab. Erst danach starten die UI-Phasen.
- [x] `CalDavClient`: PROPFIND (Collections entdecken)
- [x] `CalDavClient`: REPORT (Objekte je Collection)
- [x] `CalDavClient`: PUT (mit If-Match ETag) / DELETE
- [x] CTag-Check (billige Änderungserkennung pro Collection)
- [x] `IcalParser`: VEVENT + VTODO → App-Modelle (enough_icalendar)
- [x] Self-Signed-Zertifikat-Support (Heimserver/Unraid)
- [x] Serientermine (RRULE) expandieren (tägl./wöch./monatl./jährl.,
      INTERVAL/COUNT/UNTIL/BYDAY)
- [x] SQLite-Cache (sqflite) für Offline-Lesen (Repository mit Cache-Fallback)
- [ ] Offline-Hinweis im UI + Schreib-Queue für Offline-Änderungen
- [ ] `SyncEngine`: Delta-Sync (CTag/ETag) + Konfliktlösung

## 🔐 Phase 3 — Nextcloud-Verbindung & Onboarding
- [ ] Nextcloud Login Flow v2 (App-Passwort, nie Hauptpasswort)
- [ ] Credentials in `flutter_secure_storage` (Android Keystore)
- [ ] Onboarding-Flow + Verbindungstest
- [ ] Navigation/Design-Feinschliff

## 📅 Phase 4 — Kalender-UI
- [x] `table_calendar`: Monat / 2 Wochen / Woche mit Event-Markern
- [x] Termine farbcodiert (Kalenderfarbe) + Tagesliste
- [x] Ganztags-Events erkannt
- [x] Termin anlegen/bearbeiten/löschen (VEVENT, Editor mit Datum/Uhrzeit,
      ganztägig, Ort, Notiz, Kalenderauswahl)
- [x] Serientermine (RRULE) korrekt über Tage anzeigen

## ✔️ Phase 5 — Aufgaben-UI
- [x] Aufgabenlisten anzeigen (farbcodiert, offen-Zähler)
- [x] Abhaken (STATUS:COMPLETED) – optimistisch + CalDAV-PUT
- [x] Fälligkeitsdatum anzeigen (überfällig hervorgehoben)
- [x] Aufgabe anlegen/bearbeiten/löschen (Editor-Sheet, CalDAV PUT/DELETE)
- [ ] Unteraufgaben (RELATED-TO), Priorität nutzen
- [ ] Termin anlegen/bearbeiten/löschen (analog für VEVENT)

## 🛒 Phase 6 — Einkaufsliste
- [x] Einkauf-Tab auf VTODO/Aufgaben-Basis (wählbare Liste, persistent)
- [x] Schnell hinzufügen, abhaken, wischen zum Löschen
- [x] „Erledigte entfernen" (erledigte Artikel der Liste löschen)
- [x] Mehrere Listen wählbar (Dropdown)
- [ ] Kategorien (CATEGORIES) zum Gruppieren
- [ ] Menge im Artikel (DESCRIPTION)

## 👪 Phase 7 — Familiengruppen
- [ ] Mitglieder + Farbzuordnung
- [ ] Geteilte Kalender/Listen auswählen
- [ ] (Optional) Einladungs-/Verknüpfungslogik

## 🏠 Startseite / Dashboard
- [x] Start-Tab als erster Tab (Platzhalter)
- [ ] Übersicht: heutige Termine, fällige Aufgaben, Einkauf auf einen Blick

## ⚙️ Einstellungen
- [x] Update-Funktion (Releases öffnen) – jetzt im Einstellungs-Screen
- [x] Eigener Einstellungs-Screen (Zahnrad im Familie-Tab)
- [x] **Berechtigungen in den Einstellungen verwalten** (Benachrichtigungen:
      Status anzeigen, anfordern, Test senden)
- [ ] Theme (hell/dunkel/system) wählbar

## 🔔 Phase 8 — Benachrichtigungen
- [x] Lokale Notifications (flutter_local_notifications + timezone)
- [x] Erinnerung an anstehende Termine (Vorlaufzeit einstellbar)
- [x] Benachrichtigungs-Berechtigung anfragen (Android 13+)
- [ ] Erinnerung an fällige Aufgaben
- [ ] Reminder über Reboot hinweg / Hintergrund-Sync (workmanager)

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
