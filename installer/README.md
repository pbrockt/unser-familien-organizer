# Installer – „Unser Familien-Organizer"

Diese Skripte erzeugen echte Installer für Desktop. Sie laufen automatisch in der CI
(GitHub Actions) und werden an das jeweilige Release angehängt.

## Windows
- **`UnserFamilienOrganizer-Setup-<version>.exe`** – Installer (Inno Setup).
  Doppelklick → installiert nach `Programme\UnserFamilienOrganizer`, legt Startmenü-
  (optional Desktop-)Verknüpfung an, inkl. Deinstallation über „Apps & Features".
- `FamilyPlanner-windows-<version>.zip` – weiterhin als portable Variante (ohne Installation).

Quelle: [`windows/setup.iss`](windows/setup.iss).

## Linux
Zwei Wege:

1. **`.deb` (Debian/Ubuntu/Mint):**
   ```sh
   sudo apt install ./UnserFamilienOrganizer-<version>-amd64.deb
   ```
   Installiert nach `/opt/unser-familien-organizer`, mit Menü-Eintrag, Icon und dem
   Befehl `unser-familien-organizer`. Deinstallation: `sudo apt remove unser-familien-organizer`.

2. **Universelles Skript (jede Distribution):** das `…-linux-<version>.tar.gz` entpacken und im
   Ordner ausführen:
   ```sh
   tar -xzf FamilyPlanner-linux-<version>.tar.gz -C unser-familien-organizer
   cd unser-familien-organizer
   sudo ./install.sh
   ```
   Deinstallation: `sudo /opt/unser-familien-organizer/uninstall.sh`.

Quellen: [`linux/build-deb.sh`](linux/build-deb.sh), [`linux/install.sh`](linux/install.sh),
[`linux/uninstall.sh`](linux/uninstall.sh).
