# 📅 Unser Familien-Organizer

**Der Familienplaner für deine Nextcloud.**

Kalender, Aufgaben und Einkaufsliste für die ganze Familie – alle Daten liegen in
**deiner eigenen Nextcloud** und werden per CalDAV synchronisiert.

> 🔒 Kein fremder Server. Kein Abo. Kein fremdes Konto. Deine Daten bleiben bei dir.

---

## ✨ Was kann die App?

- 📅 **Kalender** – Monats- und Tagesansicht, mehrtägige Termine, Serientermine,
  farbige Kalender pro Person, Wetter-Vorschau und Filter (z. B. „nur Arbeit")
- ⏰ **Erinnerungen** – pro Termin einstellbar (5 Min bis 1 Stunde vorher)
- ✔️ **Aufgaben** – Listen mit Fälligkeitsdatum, Abhaken, per Drag&Drop sortieren
- 🛒 **Einkaufsliste** – schnell hinzufügen, abhaken, Erledigtes aufräumen
- 🏠 **Startseite** – Überblick über Heute & Morgen, 2-Wochen-Kalender, Countdown
  („Noch 10 Tage bis Ferien")
- 👪 **Familie** – Kalender/Listen an andere Nextcloud-Nutzer freigeben
- 📲 **Home-Widgets** (Android), **Benachrichtigungen** und **Offline-Modus**
- 🔄 **Automatische Updates** beim App-Start
- 💻 Läuft auf **Android, Windows und Linux**

---

## 📥 Installation

Fertige Versionen gibt es immer unter
**[Releases](https://github.com/pbrockt/unser-familien-organizer/releases)**.

### 📱 Android (empfohlen)
1. Unter [Releases](https://github.com/pbrockt/unser-familien-organizer/releases)
   die neueste Datei **`UnserFamilienOrganizer-<version>.apk`** herunterladen.
2. Die Datei öffnen und installieren. (Beim ersten Mal fragt Android, ob es
   Apps aus dieser Quelle installieren darf – das einmal erlauben.)
3. Fertig! Künftige Updates meldet die App selbst beim Start.

### 🪟 Windows / 🐧 Linux
Siehe die passenden Dateien im Release. Details:
[installer/README.md](installer/README.md).

---

## 🚀 Einrichtung in 3 Schritten

1. **App öffnen** und oben links auf das Profilbild bzw. unten über die
   Einstellungen (Zahnrad) zu **„Familie & Verbindung"** gehen.
2. **Mit Nextcloud verbinden:** Adresse deiner Nextcloud eingeben (z. B.
   `https://cloud.example.de`) und im Browser anmelden. Die App legt automatisch
   ein eigenes App-Passwort an – dein richtiges Passwort sieht sie nie.
   *(Heimserver mit eigenem Zertifikat? Dafür gibt es beim Anmelden eine Option.)*
3. **Loslegen:** Deine Kalender und Aufgabenlisten erscheinen automatisch. Neue
   kannst du direkt in der App anlegen.

> 💡 Eine ausführliche Schritt-für-Schritt-Anleitung mit allen Einstellungen
> (Benachrichtigungen, Wetter, Familienfreigabe, Widgets …) findest du in der
> **[📖 Anleitung](docs/ANLEITUNG.md)**.

---

## 🔄 Updates

Die App prüft **beim Start automatisch**, ob eine neue Version vorliegt, und bietet
sie zum direkten Download an. Du kannst auch jederzeit manuell suchen:
**Einstellungen → App → „Nach Updates suchen"**.

---

## 🔧 Für Technik-Interessierte

Tech-Stack, Architektur, Build-Anleitung und Mitwirken:
**[docs/TECHNIK.md](docs/TECHNIK.md)** · Roadmap: [ToDo.md](ToDo.md)

## 📜 Lizenz

[MIT](LICENSE) © 2026 pbrockt
