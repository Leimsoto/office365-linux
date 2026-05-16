#!/bin/bash
# uninstall.sh — Smart Office uninstaller for all distros
# Auto-detects distro and Office version installed
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/uninstall.sh | bash
#   bash uninstall.sh  (if run from repo)

set -euo pipefail

# ----- helpers -----
c_red()    { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn()    { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw()    { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu()    { printf '\033[1;34m%s\033[0m' "$*"; }
log()       { echo "$(c_blu '[INFO]')  $*"; }
ok()        { echo "$(c_grn '[ OK ]')  $*"; }
warn()      { echo "$(c_ylw '[WARN]')  $*"; }
die()       { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

# ----- detect distro -----
detect_family() {
  . /etc/os-release 2>/dev/null || return 1
  case "$ID" in
    debian|ubuntu|linuxmint|pop|mx|raspbian|kali|elementary|zorin|deepin|trisquel|parrot)
      echo "debian"; return ;;
    cachyos) echo "cachyos"; return ;;
    arch|manjaro|endeavouros|garuda|artix|arcolinux|reborn|chimera)
      echo "arch"; return ;;
    fedora|rhel|rocky|almalinux|centos|nobara|ultramarine|bazzite|silverblue|kinoite)
      echo "fedora"; return ;;
  esac
  case "${ID_LIKE:-}" in
    *debian*|*ubuntu*) echo "debian"; return ;;
    *arch*)            echo "arch"; return ;;
    *fedora*|*rhel*)   echo "fedora"; return ;;
  esac
  echo "unknown"
}

# ----- detect what's installed -----
detect_office() {
  if [ -d "$HOME/.Microsoft_Office_365" ]; then
    echo "365"
  elif [ -d "$HOME/.office2016" ]; then
    echo "2016"
  else
    echo "none"
  fi
}

# ----- main -----
[ "$(id -u)" -ne 0 ] || die "No ejecutes como root. El script usa sudo cuando lo necesita."

. /etc/os-release 2>/dev/null || die "No se pudo leer /etc/os-release"

FAMILY="$(detect_family)"
OFFICE_VER="$(detect_office)"

echo "==============================================="
echo "  Office Uninstaller — Auto-detect"
echo "==============================================="
echo "Distro: $PRETTY_NAME (familia: $FAMILY)"
echo "Office instalado: $OFFICE_VER"
echo

if [ "$OFFICE_VER" = "none" ]; then
  die "No se encontró ninguna instalación de Office (ni ~/.Microsoft_Office_365 ni ~/.office2016)"
fi

# ----- determine which uninstaller to use -----
case "$FAMILY:$OFFICE_VER" in
  debian:365)
    # Debian uses inline uninstall (this script handles it directly)
    log "Ejecutando desinstalación para Debian/Ubuntu..."
    # Run the debian uninstall code inline
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

    [ -d "$PREFIX" ] && [ -x "$WINECX/bin/wineserver" ] && \
      WINEPREFIX="$PREFIX" "$WINECX/bin/wineserver" -k 2>/dev/null || true
    pkill -KILL -f '/opt/winecx' 2>/dev/null || true
    pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true

    sudo rm -rf "$PREFIX" "$WINECX"
    sudo rm -f "$APPS_DIR"/{word365,excel365,powerpoint365,outlook365,access365,publisher365,kill_office}.desktop
    sudo rm -f "$ICONS_DIR"/{Word365,Excel365,Powerpoint365,Outlook365,Access365,Publisher365}.svg
    sudo rm -rf "$FONTS_DIR"
    rm -f "$DESCARGAS"/{MSO365.zip,MSO365,winecx.deb,instalar-office365-winecx.sh,instalar-office365-winecx-arch.sh}
    rm -rf "$CACHE_DIR"

    if command -v xdg-mime >/dev/null 2>&1; then
      for mime in application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document application/vnd.ms-word.document.macroEnabled.12 application/rtf application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/vnd.ms-excel.sheet.macroEnabled.12 text/csv application/vnd.ms-powerpoint application/vnd.openxmlformats-officedocument.presentationml.presentation application/vnd.ms-powerpoint.presentation.macroEnabled.12 application/vnd.ms-outlook message/rfc822 application/vnd.ms-access application/x-msaccess application/x-mspublisher; do
        xdg-mime default '' "$mime" 2>/dev/null || true
      done
    fi

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
    exit 0
    ;;
  arch:365|cachyos:365)
    UNINSTALLER="uninstall-arch.sh"
    ;;
  manjaro:365)
    # Manjaro uses Arch uninstaller
    UNINSTALLER="uninstall-arch.sh"
    ;;
  fedora:2016)
    UNINSTALLER="uninstall-office2016-fedora.sh"
    ;;
  fedora:365)
    warn "Office 365 no está disponible en Fedora. Usa Office 2016."
    die "No se puede desinstalar Office 365 en Fedora."
    ;;
  *)
    die "Combinación no soportada: distro=$FAMILY office=$OFFICE_VER"
    ;;
esac

log "Usando desinstalador: $UNINSTALLER"

# ----- run the uninstaller -----
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
REPO_URL="https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$UNINSTALLER" ]; then
  # Running from repo clone
  log "Ejecutando $SCRIPT_DIR/$UNINSTALLER"
  bash "$SCRIPT_DIR/$UNINSTALLER"
else
  # Running via curl | bash, download the uninstaller
  log "Descargando $UNINSTALLER desde GitHub..."
  TMP_UNINSTALLER="$(mktemp /tmp/office-uninstall-XXXXXX.sh)"
  curl -fsSL -o "$TMP_UNINSTALLER" "$REPO_URL/$UNINSTALLER" || \
    die "No se pudo descargar $UNINSTALLER"
  chmod +x "$TMP_UNINSTALLER"
  bash "$TMP_UNINSTALLER"
  rm -f "$TMP_UNINSTALLER"
fi

ok "Desinstalación completada."
