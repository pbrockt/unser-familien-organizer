#!/usr/bin/env bash
# Deinstallation fuer "Unser Familien-Organizer" (Linux).
#   sudo /opt/unser-familien-organizer/uninstall.sh

set -euo pipefail

APP_ID="unser-familien-organizer"
INSTALL_DIR="/opt/${APP_ID}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte mit Root-Rechten starten:  sudo ./uninstall.sh" >&2
  exit 1
fi

echo "Entferne ${APP_ID} ..."
rm -f  "/usr/local/bin/${APP_ID}"
rm -f  "/usr/share/applications/${APP_ID}.desktop"
rm -f  "/usr/share/pixmaps/${APP_ID}.png"
rm -rf "${INSTALL_DIR}"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true

echo "Fertig – ${APP_ID} wurde entfernt."
