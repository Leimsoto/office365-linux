#!/bin/bash
# Desinstalador limpio Office 365 WineCX — Arch/Artix/Manjaro/CachyOS
set -euo pipefail

# Helpers (log/ok/warn/die). Necesarios para ejecución standalone vía curl|bash.
c_red() { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn() { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw() { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu() { printf '\033[1;34m%s\033[0m' "$*"; }
log()  { echo "$(c_blu '[INFO]')  $*"; }
ok()   { echo "$(c_grn '[ OK ]')  $*"; }
warn() { echo "$(c_ylw '[WARN]')  $*"; }
die()  { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

PREFIX="$HOME/.Microsoft_Office_365"
WINECX="/opt/winecx"
APPS_DIR="/usr/share/applications"
ICONS_DIR="/usr/share/icons/hicolor/256x256/apps"
FONTS_DIR="/usr/share/fonts/Windows"
DESCARGAS="$HOME/Descargas"
CACHE_DIR="$HOME/.cache/office365-linux"

echo "==============================================="
echo "  Desinstalando Office 365 WineCX (Arch family)"
echo "==============================================="

# Detect installation method used
WAS_NATIVE=0
if [ -d "/opt/winecx/build64" ] || [ -d "/opt/winecx/build32" ]; then
  WAS_NATIVE=1
  log "Detected native build installation"
elif [ -f "/opt/winecx/bin/wine" ] && \
     file "/opt/winecx/bin/wine" 2>/dev/null | grep -q "ELF.*64-bit"; then
  # Check if it has the bundle libs (indicative of .deb installation)
  if [ -d "/opt/winecx/lib" ] && [ -d "/opt/winecx/lib32" ]; then
    # Could be either .deb or native, check for make install artifacts
    if find "/opt/winecx" -name "*.o" -type f 2>/dev/null | head -1 | grep -q "."; then
      WAS_NATIVE=1
      log "Detected native build installation (found .o artifacts)"
    else
      WAS_NATIVE=0
      log "Detected .deb installation (with bundle libs)"
    fi
  else
    WAS_NATIVE=1
    log "Detected native build installation"
  fi
else
  WAS_NATIVE=0
  log "Detected .deb installation"
fi

# Cerrar wine
[ -d "$PREFIX" ] && [ -x "$WINECX/bin/wineserver" ] && \
  WINEPREFIX="$PREFIX" "$WINECX/bin/wineserver" -k 2>/dev/null || true
pkill -KILL -f '/opt/winecx' 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true

# Prefix + WineCX (incluye bundle libs nettle/gnutls)
sudo rm -rf "$PREFIX"
if [ "${WAS_NATIVE:-0}" = "1" ]; then
  warn "Removing native build WineCX..."
  # Native builds don't have a clean uninstall, just remove the directory
  sudo rm -rf /opt/winecx
else
  # .deb installation
  sudo rm -rf "$WINECX"
fi

# .desktop entries
sudo rm -f "$APPS_DIR"/{word365,excel365,powerpoint365,outlook365,access365,publisher365,kill_office}.desktop

# Íconos
sudo rm -f "$ICONS_DIR"/{Word365,Excel365,Powerpoint365,Outlook365,Access365,Publisher365}.svg

# Fonts globales
sudo rm -rf "$FONTS_DIR"

# Symlinks en ~/Descargas
rm -f "$DESCARGAS/MSO365.zip" "$DESCARGAS/MSO365" "$DESCARGAS/winecx.deb" \
      "$DESCARGAS/instalar-office365-winecx.sh" \
      "$DESCARGAS/instalar-office365-winecx-arch.sh" \
      "$DESCARGAS/instalar-office2016-fedora.sh" \
      "$DESCARGAS/arch-winecx-libs.tar.zst"

# Cache descarga
rm -rf "$CACHE_DIR"

# Backup pacman.conf restaurable
if [ -f /etc/pacman.conf.office365-bak ]; then
  echo
  echo "Backup de pacman.conf disponible en /etc/pacman.conf.office365-bak"
  read -r -p "¿Restaurar /etc/pacman.conf original? [y/N]: " ans </dev/tty
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo cp /etc/pacman.conf.office365-bak /etc/pacman.conf
    sudo rm -f /etc/pacman.conf.office365-bak
    echo "[OK] pacman.conf restaurado"
  fi
fi

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
echo "Paquetes pacman/AUR instalados como dependencia se conservan."
echo "Para removerlos manualmente (revisar antes):"
echo "  sudo pacman -Rns wine winetricks msitools ttf-ms-fonts \\"
echo "    lib32-mesa lib32-libdrm lib32-vulkan-radeon lib32-vulkan-intel lib32-nvidia-utils \\"
echo "    lib32-libtasn1 lib32-libidn2 lib32-p11-kit lib32-gmp lib32-libunistring \\"
echo "    lib32-libnghttp2 lib32-libgpg-error lib32-libgcrypt"
