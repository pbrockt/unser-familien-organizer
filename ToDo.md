# 📋 FamilyPlanner — ToDo / Roadmap

Selbst-gehosteter Familienplaner (Kalender + Aufgaben + Einkaufsliste).
Alle Daten leben in **Nextcloud** via **CalDAV**. Kein eigener Server, kein Abo.

Stand: Juni 2026 · App: Flutter (Android, später Web)

---

## 🐞 Bugs
- [x] Schutz: Löschen eines Termins muss bestätigt werden, Bestätigen-Button
      erst nach 5 Sekunden klickbar (gegen versehentliches Serien-Löschen)
- [x] **Serientermin doppelt nach Bearbeitung** (FIX in test014): Override-
      Instanzen (`RECURRENCE-ID`) werden jetzt bevorzugt, die Serien-Instanz
      an dem Tag ausgelassen; `EXDATE` (ausgenommene Tage) wird beachtet.
- [x] **Löschen einer Instanz löscht ganze Serie** (FIX in test014): Beim
      Löschen eines Serientermins fragt der Editor jetzt „Nur diesen" vs
      „Ganze Serie". „Nur diesen" setzt ein `EXDATE` (und entfernt eine evtl.
      Override-Instanz) statt das ganze .ics zu löschen.
- [x] Einzelne Serien-Instanz **bearbeiten/verschieben** (FIX in test015):
      Editor fragt beim Speichern „Nur diesen / Ganze Serie"; „Nur diesen"
      legt einen Override (RECURRENCE-ID) an, „Ganze Serie" ändert nur den
      Master (Overrides bleiben erhalten).
- [ ] Ganztags-Serien: EXDATE/Override als VALUE=DATE (umgesetzt, praktisch
      prüfen)

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
- [x] Offline-Schreiben: Queue (SQLite) + optimistischer Cache, automatisches
      Abspielen beim nächsten Online-Laden; Dashboard-Hinweis „X Änderungen
      warten auf Sync" mit manuellem Sync
- [x] Schneller App-Start: gecachte Daten sofort anzeigen, im Hintergrund
      aktualisieren (stale-while-revalidate)
- [x] Delta-Sync via CTag: unveränderte Kalender/Listen werden nicht neu
      heruntergeladen (deutlich schnellerer Sync)
- [x] Konfliktlösung bei ETag-Mismatch (HTTP 412): beim Bearbeiten Dialog
      „Meine behalten" (überschreiben) vs „Aktuelle Version laden"; in der
      Offline-Queue gewinnt die bewusste Offline-Änderung (force); Abhaken
      bei Konflikt automatisch erzwungen

## 🔐 Phase 3 — Nextcloud-Verbindung & Onboarding
- [x] Nextcloud Login Flow v2 (Anmeldung im Browser, App-Passwort automatisch)
- [x] Credentials in `flutter_secure_storage` (Android Keystore)
- [x] Manuell-mit-App-Passwort als Fallback + Verbindungstest
- [x] Self-Signed-Zertifikat-Option beim Login

## 📅 Phase 4 — Kalender-UI
- [x] `table_calendar`: Monat / 2 Wochen / Woche mit Event-Markern
- [x] Termine farbcodiert (Kalenderfarbe) + Tagesliste
- [x] Ganztags-Events erkannt
- [x] Termin anlegen/bearbeiten/löschen (VEVENT, Editor mit Datum/Uhrzeit,
      ganztägig, Ort, Notiz, Kalenderauswahl)
- [x] Serientermine (RRULE) korrekt über Tage anzeigen
- [x] **Mehrtägige / tagübergreifende Termine an allen Tagen anzeigen**
      (Kalender-Tagesliste + Dashboard)
- [x] **Datumsauswahl beginnt am Montag** (deutsche Lokalisierung der Picker)
- [x] **Uhrzeit-/Termin-Anzeige aufgehübscht** (Zeit-Block, mehrtägig-Hinweis)
- [ ] Mehrtägige Termine als durchgehender Balken im Monatsraster

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
- [x] Mitglieder & Farben: Kalender lokal benennen, Farbe wählen, ein-/
      ausblenden (Mitglieder-Screen im Familie-Tab)
- [x] Farb-Legende im Kalender (zugleich Schnellfilter pro Person)
- [x] Sichtbarkeitsfilter wirkt auf Kalender + Dashboard
- [x] Mitglieder-Farbe & -Name auch in Aufgaben/Einkauf; Mitglieder-Screen
      deckt alle Listen ab (Termine + Aufgaben), Legende zeigt nur Kalender
- [ ] (Optional) Einladungs-/Verknüpfungslogik

## 🏠 Startseite / Dashboard
- [x] Start-Tab als erster Tab
- [x] **Dashboard „Heute & morgen"** (Planily-inspiriert, Gradient-Header):
  - [x] Begrüßung (tageszeitabhängig) + Datum
  - [x] **Heute**: Termine des Tages (Uhrzeit, Titel, farbcodiert)
  - [x] **Morgen**: Termine von morgen
  - [x] **Fällige Aufgaben**: heute fällig + überfällig (mit Abhaken)
  - [x] **Einkauf**: Hinweis-Karte, wenn offene Artikel
  - [x] Leerzustände („Heute nichts geplant 🎉")
  - [x] Tippen öffnet Termin/Aufgabe bzw. „Alle" springt in den Tab
  - [x] Pull-to-Refresh, nutzt Offline-Cache
- [ ] Optional: Mitglieder-Filter / Wetter / Geburtstage hervorheben

## 🧩 Home-Screen-Widgets (Android)
- [x] Kalender: Heute / Heute+Morgen / Woche / Monat
- [x] Aufgaben (offene) + Einkauf (offene Artikel)
- [x] Native, schlicht (Text), aktualisieren im Hintergrund (workmanager) und
      beim App-Öffnen; Antippen öffnet den passenden Tab
- [ ] Optional: Deep-Link-Navigation zum Tab beim Antippen
- [ ] Optional: scrollbare Listen-Widgets / Monatsraster als Bild

## 🎨 Design
- [x] Warmes Planily-Theme (Creme-Hintergrund, Orange-Akzent, braune Schrift,
      runde weiße Karten, dekorative Pastell-„Blobs")
- [x] Dashboard im Screenshot-Stil: Begrüßung + Avatar + Zahnrad, anstehende
      Termine als horizontale Karten, Listen mit Fortschritt
- [x] Ruhiger einfarbiger Hintergrund mit leichtem Verlauf + sehr dezenten
      Kreisen (statt bunter Blobs)
- [x] Anstehende Termine nur heute + max. morgen, mit klarer „Heute/Morgen"-
      Markierung (heute leer → morgen wird gezeigt)
- [ ] Feinschliff nach Screenshot-Vorlage (Abstände, Familien-Pille)
- [x] Theme-Wahl (System/Hell/Dunkel) in den Einstellungen; Startseite +
      Hintergrund passen sich Hell/Dunkel an

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
- [x] Erinnerung an fällige Aufgaben (am Fälligkeitstag)
- [x] Reminder überleben Neustart (Boot-Receiver)
- [x] Hintergrund-Sync (workmanager): synchronisiert ~alle 2 h im Hintergrund
      und plant Erinnerungen neu – neue Termine werden auch ohne App-Öffnen
      berücksichtigt (an/aus über die Erinnerungs-Einstellung)

## 🔒 Phase 9 — Sicherheit
- [ ] Keystore/Secrets-Handling final
- [ ] Self-Signed-Cert UX (Vertrauen bestätigen)

## 🖥️ Desktop (Windows + Linux)
- [x] Windows-Build (.exe, portabel als ZIP) + Linux-Build (Bundle als tar.gz)
      aus demselben Flutter-Code; CI-Jobs auf windows-latest/ubuntu-latest
- [x] Plattform-Weichen: Benachrichtigungen/Widgets/Hintergrund-Sync nur Android;
      SQLite über sqflite_common_ffi, DB-Pfad via path_provider
- [ ] Desktop-Politur: Fenstergröße/-titel, ggf. Tray, Timer-Sync
- [ ] Echte Installer: Windows MSIX/Inno-Setup, Linux AppImage/.deb

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
