#!/bin/bash
# Desinstalador limpio Office 365 WineCX — Debian/Ubuntu
set -e

PREFIX="$HOME/.Microsoft_Office_365"
WINECX="/opt/winecx"
APPS_DIR="/usr/share/applications"
ICONS_DIR="/usr/share/icons/hicolor/256x256/apps"
FONTS_DIR="/usr/share/fonts/Windows"
DESCARGAS="$HOME/Descargas"
CACHE_DIR="$HOME/.cache/office365-linux"

echo "==============================================="
echo "  Desinstalando Office 365 WineCX (Debian)"
echo "==============================================="

# Cerrar wine
[ -d "$PREFIX" ] && [ -x "$WINECX/bin/wineserver" ] && \
  WINEPREFIX="$PREFIX" "$WINECX/bin/wineserver" -k 2>/dev/null || true
pkill -KILL -f '/opt/winecx' 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true

# Prefix + WineCX
sudo rm -rf "$PREFIX"
sudo rm -rf "$WINECX"

# .desktop entries
sudo rm -f "$APPS_DIR"/{word365,excel365,powerpoint365,outlook365,access365,publisher365,kill_office}.desktop

# Íconos
sudo rm -f "$ICONS_DIR"/{Word365,Excel365,Powerpoint365,Outlook365,Access365,Publisher365}.svg

# Fonts globales
sudo rm -rf "$FONTS_DIR"

# Symlinks en ~/Descargas
rm -f "$DESCARGAS/MSO365.zip" "$DESCARGAS/MSO365" "$DESCARGAS/winecx.deb" \
      "$DESCARGAS/instalar-office365-winecx.sh" "$DESCARGAS/instalar-office365-winecx-arch.sh" \
      "$DESCARGAS/instalar-office365-winecx-fedora.sh"

# Cache descarga
rm -rf "$CACHE_DIR"

# xdg-mime defaults
if command -v xdg-mime >/dev/null 2>&1; then
  for mime in \
    application/msword \
    application/vnd.openxmlformats-officedocument.wordprocessingml.document \
    application/vnd.ms-word.document.macroEnabled.12 \
    application/rtf \
    application/vnd.ms-excel \
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
    application/vnd.ms-excel.sheet.macroEnabled.12 \
    text/csv \
    application/vnd.ms-powerpoint \
    application/vnd.openxmlformats-officedocument.presentationml.presentation \
    application/vnd.ms-powerpoint.presentation.macroEnabled.12 \
    application/vnd.ms-outlook \
    message/rfc822 \
    application/vnd.ms-access \
    application/x-msaccess \
    application/x-mspublisher; do
    xdg-mime default '' "$mime" 2>/dev/null || true
  done
fi

# Refrescar caches
sudo fc-cache -f >/dev/null 2>&1 || true
sudo gtk-update-icon-cache "$ICONS_DIR/.." 2>/dev/null || true
sudo update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo
echo "[OK] Office 365 + WineCX desinstalados completamente."
echo
echo "Paquetes apt instalados como dependencia se conservan."
echo "Para removerlos manualmente (revisar antes):"
echo "  sudo apt-get remove --purge winecx wine32:i386 winetricks msitools"
echo "  sudo apt-get autoremove"
