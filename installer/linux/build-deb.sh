#!/usr/bin/env bash
# Baut ein .deb-Paket fuer "Unser Familien-Organizer".
# Aufruf (in der CI):   bash installer/linux/build-deb.sh <version>
# Erwartet den fertigen Linux-Build unter build/linux/x64/release/bundle
# und das Icon unter design/icons/icon.png.

set -euo pipefail

VERSION="${1:?Version angeben, z.B. 0.30.1}"
APP_ID="unser-familien-organizer"
APP_NAME="Unser Familien-Organizer"
BINARY="family_planner"
MAINTAINER="PBrockt <phillipp.brosch@aus-hesel.de>"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="${REPO_ROOT}/build/linux/x64/release/bundle"
ICON_SRC="${REPO_ROOT}/design/icons/icon.png"
PKG_DIR="${REPO_ROOT}/build/deb/${APP_ID}_${VERSION}"

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "Fehler: Linux-Bundle nicht gefunden: ${BUNDLE_DIR}" >&2
  exit 1
fi

echo "Erzeuge .deb-Struktur in ${PKG_DIR} ..."
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/opt/${APP_ID}"
mkdir -p "${PKG_DIR}/usr/share/applications"
mkdir -p "${PKG_DIR}/usr/share/pixmaps"
mkdir -p "${PKG_DIR}/usr/bin"

# App-Dateien.
cp -a "${BUNDLE_DIR}/." "${PKG_DIR}/opt/${APP_ID}/"
chmod +x "${PKG_DIR}/opt/${APP_ID}/${BINARY}"

# Icon.
[[ -f "${ICON_SRC}" ]] && cp "${ICON_SRC}" "${PKG_DIR}/usr/share/pixmaps/${APP_ID}.png"

# Startmenue-Eintrag.
cat > "${PKG_DIR}/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Der Familienplaner fuer die Nextcloud
Exec=/opt/${APP_ID}/${BINARY}
Icon=${APP_ID}
Terminal=false
Categories=Office;Calendar;
StartupWMClass=family_planner
EOF

# Symlink in den PATH (relativ, damit dpkg ihn sauber verwaltet).
ln -sf "/opt/${APP_ID}/${BINARY}" "${PKG_DIR}/usr/bin/${APP_ID}"

# Installierte Groesse (KB) fuer die control-Datei.
INSTALLED_SIZE="$(du -sk "${PKG_DIR}/opt" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: ${APP_ID}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libsecret-1-0, libsqlite3-0
Description: ${APP_NAME}
 Selbst-gehosteter Familienplaner (Kalender, Aufgaben, Einkaufsliste)
 per CalDAV mit Nextcloud.
EOF

# Desktop-Datenbank nach Installation aktualisieren.
cat > "${PKG_DIR}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
exit 0
EOF
chmod 0755 "${PKG_DIR}/DEBIAN/postinst"

OUT="${REPO_ROOT}/UnserFamilienOrganizer-${VERSION}-amd64.deb"
dpkg-deb --root-owner-group --build "${PKG_DIR}" "${OUT}"
echo "Fertig: ${OUT}"
