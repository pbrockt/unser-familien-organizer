#!/usr/bin/env bash
# Installations-Skript fuer "Unser Familien-Organizer" (Linux, universell).
# Im entpackten Ordner ausfuehren:   sudo ./install.sh
# Kopiert die App nach /opt, legt Startmenue-Eintrag + Icon an und einen
# Befehl "unser-familien-organizer" in /usr/local/bin.

set -euo pipefail

APP_ID="unser-familien-organizer"
APP_NAME="Unser Familien-Organizer"
BINARY="family_planner"
INSTALL_DIR="/opt/${APP_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte mit Root-Rechten starten:  sudo ./install.sh" >&2
  exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/${BINARY}" ]]; then
  echo "Fehler: '${BINARY}' nicht im aktuellen Ordner gefunden." >&2
  echo "Bitte das Skript aus dem entpackten App-Ordner ausfuehren." >&2
  exit 1
fi

echo "Installiere ${APP_NAME} nach ${INSTALL_DIR} ..."
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# App-Dateien kopieren (uninstall.sh bleibt fuer spaeter erhalten).
cp -a "${SCRIPT_DIR}/." "${INSTALL_DIR}/"
rm -f "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/${APP_ID}.png"
chmod +x "${INSTALL_DIR}/${BINARY}" "${INSTALL_DIR}/uninstall.sh"

# Icon installieren.
if [[ -f "${SCRIPT_DIR}/${APP_ID}.png" ]]; then
  install -Dm644 "${SCRIPT_DIR}/${APP_ID}.png" "/usr/share/pixmaps/${APP_ID}.png"
fi

# Startmenue-Eintrag (.desktop).
cat > "/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Der Familienplaner fuer die Nextcloud
Exec=${INSTALL_DIR}/${BINARY}
Icon=${APP_ID}
Terminal=false
Categories=Office;Calendar;
StartupWMClass=family_planner
EOF

# Befehl in den PATH legen.
ln -sf "${INSTALL_DIR}/${BINARY}" "/usr/local/bin/${APP_ID}"

# Desktop-Datenbank aktualisieren (falls vorhanden).
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache  >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true

echo "Fertig! Start ueber das Anwendungsmenue oder mit:  ${APP_ID}"
echo "Deinstallieren mit:  sudo ${INSTALL_DIR}/uninstall.sh"
