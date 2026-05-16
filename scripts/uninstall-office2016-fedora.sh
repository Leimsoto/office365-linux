#!/bin/bash
# Desinstalador limpio Office 2016 — Fedora/RHEL
set -e

PREFIX="$HOME/.office2016"
WINECX="/opt/winecx"
LAUNCHERS="/opt/wine/launchers"
APPS_DIR="/usr/share/applications"
ICONS_DIR="/usr/share/icons/hicolor/256x256/apps"
FONTS_DIR="/usr/share/fonts/Windows"
DESCARGAS="$HOME/Descargas"

echo "==============================================="
echo "  Desinstalando Office 2016 (Fedora)"
echo "==============================================="

[ -d "$PREFIX" ] && [ -x "$WINECX/bin/wineserver" ] && \
  WINEPREFIX="$PREFIX" "$WINECX/bin/wineserver" -k 2>/dev/null || true
pkill -KILL -f "$PREFIX" 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE' 2>/dev/null || true

sudo rm -rf "$PREFIX"
sudo rm -rf "$WINECX"
sudo rm -rf "$LAUNCHERS"
sudo rmdir /opt/wine 2>/dev/null || true

sudo rm -f "$APPS_DIR"/{word2016,excel2016,powerpoint2016,outlook2016,access2016,publisher2016}.desktop
sudo rm -f "$ICONS_DIR"/{word2016,excel2016,powerpoint2016,outlook2016,access2016,publisher2016}.png

sudo rm -rf "$FONTS_DIR"
sudo rm -rf /usr/share/wine/gecko /usr/share/wine/mono

# Cleanup ISO + extract + temp
rm -rf "$DESCARGAS/OfPro" "$DESCARGAS/SW_DVD5_Office_Professional_Plus_2016_W32_Spanish_MLF_X20-41360"
rm -f  "$DESCARGAS/OfPro.ISO"
rm -rf "$DESCARGAS/Requerimientos Office 2016"
rm -rf "$DESCARGAS/FuentesOffice365"
rm -f  "$DESCARGAS/winecx.zip"
rm -f  "$DESCARGAS/Requerimientos-Office-2016.zip"
rm -f  "$DESCARGAS/FuentesOffice365.zip"

sudo fc-cache -f >/dev/null 2>&1 || true
sudo gtk-update-icon-cache "$ICONS_DIR/.." 2>/dev/null || true
sudo update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo "[OK] Office 2016 desinstalado."
echo
echo "Para borrar deps dnf (revisar antes):"
echo "  sudo dnf remove wine winetricks cabextract msitools samba-winbind"
echo "  sudo dnf autoremove"
