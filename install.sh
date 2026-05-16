#!/usr/bin/env bash
# install.sh — Office 365 (WineCX) installer for Debian/Ubuntu AND Arch/Manjaro/CachyOS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash -s -- --yes
#
# Flags:
#   --yes / -y      Non-interactive, assume yes
#   --keep-cache    Don't remove downloaded archives after install
#   --tag=vX.Y.Z    Pin a specific release tag (default: v1.0.0 for assets)
#   --no-verify     Skip SHA256 verification (NOT recommended)
#   --family=auto   Force distro family: auto|debian|arch|manjaro|cachyos|fedora
#   --office=365    Office 365 (default on Debian/Arch; NOT supported on Fedora)
#   --office=2016   Office 2016 (auto-selected on Fedora; requires manual ISO)
#
# Fedora behaviour: when --office is not passed, Office 2016 is auto-selected
# (Office 365 Click-to-Run no funciona en Fedora). Pasar --office=365 en Fedora
# falla con mensaje claro.
#
# CachyOS special: when detected, shows a switch menu with 2 options:
#   Option 1 (DEFAULT/RECOMMENDED): Debian .deb (most compatible)
#   Option 2 (Fallback): winecx_cachy.zip (CachyOS native build)

set -euo pipefail
IFS=$'\n\t'

# ----- config -----
REPO_OWNER="Leimsoto"
REPO_NAME="office365-linux"
DEFAULT_TAG="v1.0.0"
INSTALLER_BRANCH="${OFFICE365_INSTALLER_BRANCH:-main}"
WORKDIR="${OFFICE365_WORKDIR:-$HOME/.cache/office-linux}"
ASSETS=(
  "MSO365.zip.part00.bin"
  "MSO365.zip.part01.bin"
  "winecx.deb"
)
# SHA256 of each asset and of the joined MSO365.zip. Updated on release.
declare -A SHA256=(
  ["MSO365.zip.part00.bin"]="7360442d7826da91a8c2f1cc7df05259422a507b42d503ea7a639f9385368947"
  ["MSO365.zip.part01.bin"]="3402addb7ac8e653c414894066203cf3b88e254e7aa0bb0b4340d4a409676eae"
  ["winecx.deb"]="1196feacf0691ef461d8bf7c29e0f3ae29740b04e6d00fed1740dafaf4f19d3c"
  ["MSO365.zip"]="a8029fdff0f30b939b56f11c05312cdf5d6ed22481a3122b130420f4260786da"
)

# CachyOS-specific assets (fallback)
CACHY_ZIP="winecx_cachy.zip"
CACHY_ZIP_SHA="4dfe3b8b89edc2a65a98f92f19b4ab51b3504052853f1b71f38ff91dd2886219"
CACHY_ZIP_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_cachy.zip"

# Arch-specific assets (fallback)
ARCH_ZIP="winecx_arch.zip"
ARCH_ZIP_SHA="2459b0920a33a15791100648393e168fe296f248abdb7ae2eb44c932e252c6fe"
ARCH_ZIP_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_arch.zip"

# Manjaro-specific assets (fallback)
MANJARO_ZIP="winecx_manjaro.zip"
MANJARO_ZIP_SHA="456bbe42831fa2e6ac7cc48529ab183e4066383136eae14c80b412d75ea63bc0"
MANJARO_ZIP_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_manjaro.zip"

# ----- args -----
ASSUME_YES=0
KEEP_CACHE=0
TAG="$DEFAULT_TAG"
DO_VERIFY=1
FAMILY_OVERRIDE="auto"
OFFICE_VER="365"
OFFICE_VER_EXPLICIT=0
CACHY_CHOICE=""  # Will be set by CachyOS menu

for arg in "$@"; do
  case "$arg" in
    -y|--yes)        ASSUME_YES=1 ;;
    --keep-cache)    KEEP_CACHE=1 ;;
    --no-verify)     DO_VERIFY=0 ;;
    --tag=*)         TAG="${arg#--tag=}" ;;
    --family=*)      FAMILY_OVERRIDE="${arg#--family=}" ;;
    --office=*)      OFFICE_VER="${arg#--office=}"; OFFICE_VER_EXPLICIT=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ----- helpers -----
c_red()    { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn()    { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw()    { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu()    { printf '\033[1;34m%s\033[0m' "$*"; }
log()       { echo "$(c_blu '[INFO]')  $*"; }
ok()        { echo "$(c_grn '[ OK ]')  $*"; }
warn()      { echo "$(c_ylw '[WARN]')  $*"; }
die()       { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  local prompt="${1:-Continuar?} [y/N]: "
  read -r -p "$prompt" ans </dev/tty || die "TTY no disponible. Usar --yes."
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ----- banner -----
cat <<'BANNER'
=========================================================
   Microsoft Office 365 (WineCX) — Linux installer
   Repo: https://github.com/Leimsoto/office365-linux
   License: GPL-3.0
=========================================================
BANNER

# ----- preflight: distro family detection -----
[ "$(id -u)" -ne 0 ] || die "No ejecutes como root. El script usa sudo cuando lo necesita."

. /etc/os-release 2>/dev/null || die "No se pudo leer /etc/os-release"

detect_family() {
  case "$ID" in
    debian|ubuntu|linuxmint|pop|mx|raspbian|kali|elementary|zorin|deepin|trisquel|parrot)
      echo "debian"; return ;;
    cachyos)
      echo "cachyos"; return ;;
    manjaro)
      echo "manjaro"; return ;;
    arch|endeavouros|garuda|artix|arcolinux|reborn|chimera)
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

FAMILY="$FAMILY_OVERRIDE"
[ "$FAMILY" = "auto" ] && FAMILY="$(detect_family)"

case "$FAMILY" in
  debian)  ok "Distro: $PRETTY_NAME (familia: Debian/Ubuntu)" ;;
  arch)    ok "Distro: $PRETTY_NAME (familia: Arch/Artix)" ;;
  manjaro) ok "Distro: $PRETTY_NAME (familia: Manjaro)" ;;
  cachyos) ok "Distro: $PRETTY_NAME (familia: CachyOS)" ;;
  fedora)  ok "Distro: $PRETTY_NAME (familia: Fedora/RHEL)" ;;
  *)       die "Distro no soportada: $PRETTY_NAME. Forzar con --family=debian|arch|manjaro|cachyos|fedora." ;;
esac

# Fedora no soporta Office 365 (Click-to-Run no funciona). Si el usuario no
# pasó --office explícitamente, auto-cambiar a 2016. Si pasó --office=365 a
# propósito, fallar más abajo con mensaje claro.
if [ "$FAMILY" = "fedora" ] && [ "$OFFICE_VER_EXPLICIT" = "0" ]; then
  OFFICE_VER="2016"
  log "Fedora detectada — usando Office 2016 (Office 365 no disponible en Fedora)"
fi

# ----- CachyOS switch menu -----
if [ "$FAMILY" = "cachyos" ] && [ "$ASSUME_YES" = "0" ]; then
  cat <<'CACHY_MENU'
=========================================================
   CachyOS Wine Selection Menu
=========================================================
   Office 365 requires WineCX (CrossOver-Wine) to work properly.

   Option 1 (RECOMMENDED, DEFAULT):
     Install using Debian .deb package
     ✅ Most compatible
     ✅ Best for Click-to-Run Office 365
     ✅ Tested and stable

   Option 2 (Fallback only):
     Install using CachyOS native build (winecx_cachy.zip)
     ⚠️  Use ONLY if .deb fails
     ⚠️  NOT recommended for first installation
     ⚠️  Last resort if compatibility issues

=========================================================
CACHY_MENU
  read -r -p "Select option [1] (1=Recommended, 2=Fallback): " CACHY_CHOICE </dev/tty
  CACHY_CHOICE="${CACHY_CHOICE:-1}"
  
  if [ "$CACHY_CHOICE" = "2" ]; then
    warn "Using CachyOS native build (fallback mode)"
    export CACHY_USE_NATIVE=1
  else
    ok "Using Debian .deb (recommended mode)"
    export CACHY_USE_NATIVE=0
  fi
fi

# ----- per-family installer script + size estimate -----
case "$FAMILY:$OFFICE_VER" in
  debian:365)
    INSTALLER_FILE="instalar-office365-winecx.sh"
    DL_SIZE_MSG="~2.3 GB de assets"
    SYS_CHANGES="apt, /opt/winecx, /usr/share/applications"
    ;;
  arch:365)
    INSTALLER_FILE="instalar-office365-winecx-arch.sh"
    DL_SIZE_MSG="~2.3 GB de assets + 4 MB bundle nettle/gnutls"
    SYS_CHANGES="pacman/AUR, /opt/winecx, /usr/share/applications, /etc/pacman.conf (multilib)"
    ;;
  manjaro:365)
    # Manjaro uses same Arch script by default, with fallback to winecx_manjaro.zip
    INSTALLER_FILE="instalar-office365-winecx-arch.sh"
    DL_SIZE_MSG="~2.3 GB de assets + 4 MB bundle nettle/gnutls (fallback: winecx_manjaro.zip)"
    SYS_CHANGES="pacman, /opt/winecx, /usr/share/applications, /etc/pacman.conf (multilib)"
    ;;
  cachyos:365)
    if [ "${CACHY_USE_NATIVE:-0}" = "1" ]; then
      # Fallback mode: use CachyOS native build
      INSTALLER_FILE="instalar-office365-winecx-arch.sh"
      export CACHY_NATIVE_MODE=1
      DL_SIZE_MSG="~1.0 GB winecx_cachy.zip (CachyOS native build - FALLBACK MODE)"
      SYS_CHANGES="pacman, /opt/winecx (native build), /usr/share/applications"
    else
      # Default mode: use Debian .deb (recommended)
      INSTALLER_FILE="instalar-office365-winecx-arch.sh"
      DL_SIZE_MSG="~2.3 GB de assets + 4 MB bundle nettle/gnutls (using .deb - RECOMMENDED)"
      SYS_CHANGES="pacman/AUR, /opt/winecx (from .deb), /usr/share/applications, /etc/pacman.conf (multilib)"
    fi
    ;;
  fedora:2016)
    INSTALLER_FILE="instalar-office2016-fedora.sh"
    DL_SIZE_MSG="~432 MB Wine Fedora + ~367 MB requerimientos. ISO Office 2016 + Activador deben estar en \$HOME/Descargas"
    SYS_CHANGES="dnf (muchas -devel), /opt/winecx, /opt/wine/launchers, /usr/share/applications, RPM Fusion, ~/.office2016 prefix"
    ;;
  fedora:*)
    die "Office 365 no está disponible en Fedora (Click-to-Run no funciona).
       Para instalar Office 2016 en Fedora usa:
         curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/install.sh | bash
       (sin --office=365). El script auto-selecciona Office 2016 en Fedora."
    ;;
  *)
    die "Combinación no soportada: family=$FAMILY office=$OFFICE_VER. Office 2016 solo disponible en --family=fedora."
    ;;
esac

if ! confirm "Se descargarán $DL_SIZE_MSG y se modificará el sistema ($SYS_CHANGES). ¿Continuar?"; then
  die "Cancelado por el usuario."
fi

# ----- ensure tools -----
sudo -v || die "sudo requerido."

ensure_cmd_debian() {
  command -v "$1" >/dev/null 2>&1 || { log "Instalando $2 (apt)"; sudo apt-get install -y "$2" || die "No se pudo instalar $2"; }
}
ensure_cmd_arch() {
  command -v "$1" >/dev/null 2>&1 || { log "Instalando $2 (pacman)"; sudo pacman -S --noconfirm --needed "$2" || die "No se pudo instalar $2"; }
}
ensure_cmd_fedora() {
  command -v "$1" >/dev/null 2>&1 || { log "Instalando $2 (dnf)"; sudo dnf install -y "$2" || die "No se pudo instalar $2"; }
}

case "$FAMILY" in
  debian)
    ensure_cmd_debian curl curl
    ensure_cmd_debian unzip unzip
    ensure_cmd_debian sha256sum coreutils
    ;;
  arch|manjaro|cachyos)
    ensure_cmd_arch curl curl
    ensure_cmd_arch unzip unzip
    ensure_cmd_arch sha256sum coreutils
    ensure_cmd_arch tar tar
    ensure_cmd_arch zstd zstd
    ;;
  fedora)
    ensure_cmd_fedora curl curl
    ensure_cmd_fedora unzip unzip
    ensure_cmd_fedora sha256sum coreutils
    ;;
esac

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----- download assets (skip si Office 2016 — usa otros assets) -----
BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}"

if [ "$OFFICE_VER" = "365" ]; then
  # Download standard assets
  for a in "${ASSETS[@]}"; do
    if [ -f "$a" ] && [ "$DO_VERIFY" = "1" ] && echo "${SHA256[$a]}  $a" | sha256sum -c --status; then
      ok "Cache hit: $a"
      continue
    fi
    log "Descargando $a"
    curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$a.part" "$BASE_URL/$a"
    mv "$a.part" "$a"
    if [ "$DO_VERIFY" = "1" ]; then
      echo "${SHA256[$a]}  $a" | sha256sum -c --status || die "SHA256 mismatch en $a"
      ok "Verificado $a"
    fi
  done

  # ----- join parts -----
  log "Reuniendo MSO365.zip desde partes"
  cat MSO365.zip.part00.bin MSO365.zip.part01.bin > MSO365.zip
  if [ "$DO_VERIFY" = "1" ]; then
    echo "${SHA256[MSO365.zip]}  MSO365.zip" | sha256sum -c --status \
      || die "SHA256 mismatch en MSO365.zip tras unir. Repite la descarga."
    ok "Verificado MSO365.zip"
  fi

  # ----- extract -----
  log "Extrayendo MSO365.zip"
  rm -rf MSO365
  unzip -q -o MSO365.zip
  cp -f winecx.deb MSO365/winecx.deb
  
  # ----- CachyOS: download fallback zip if in native mode -----
  if [ "$FAMILY" = "cachyos" ] && [ "${CACHY_USE_NATIVE:-0}" = "1" ]; then
    if [ ! -f "$CACHY_ZIP" ] || ! echo "$CACHY_ZIP_SHA  $CACHY_ZIP" | sha256sum -c --status; then
      log "Descargando $CACHY_ZIP (CachyOS native build)"
      curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$CACHY_ZIP" "$CACHY_ZIP_URL"
      echo "$CACHY_ZIP_SHA  $CACHY_ZIP" | sha256sum -c --status || \
        { echo "ERROR: SHA256 mismatch en $CACHY_ZIP" >&2; exit 1; }
    fi
  fi
  
  # ----- Manjaro: download fallback zip if needed -----
  if [ "$FAMILY" = "manjaro" ]; then
    if [ ! -f "$MANJARO_ZIP" ] || ! echo "$MANJARO_ZIP_SHA  $MANJARO_ZIP" | sha256sum -c --status; then
      log "Descargando $MANJARO_ZIP (Manjaro fallback)"
      curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$MANJARO_ZIP" "$MANJARO_ZIP_URL"
      echo "$MANJARO_ZIP_SHA  $MANJARO_ZIP" | sha256sum -c --status || \
        { echo "ERROR: SHA256 mismatch en $MANJARO_ZIP" >&2; exit 1; }
    fi
  fi
  
  # ----- Arch: download fallback zip if needed -----
  if [ "$FAMILY" = "arch" ]; then
    if [ ! -f "$ARCH_ZIP" ] || ! echo "$ARCH_ZIP_SHA  $ARCH_ZIP" | sha256sum -c --status; then
      log "Descargando $ARCH_ZIP (Arch fallback)"
      curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$ARCH_ZIP" "$ARCH_ZIP_URL"
      echo "$ARCH_ZIP_SHA  $ARCH_ZIP" | sha256sum -c --status || \
        { echo "ERROR: SHA256 mismatch en $ARCH_ZIP" >&2; exit 1; }
    fi
  fi
else
  log "Office 2016 — assets serán descargados por el installer (winecx.zip + Requerimientos + Fuentes)"
fi

INSTALLER_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${INSTALLER_BRANCH}/scripts/${INSTALLER_FILE}"
log "Descargando script principal: $INSTALLER_RAW"
curl -fL -o "$INSTALLER_FILE" "$INSTALLER_RAW"
chmod +x "$INSTALLER_FILE"

# Legacy scripts esperan $HOME/Descargas. Symlinks.
DESCARGAS="$HOME/Descargas"
mkdir -p "$DESCARGAS"
ln -sf "$WORKDIR/MSO365.zip"          "$DESCARGAS/MSO365.zip"
ln -sf "$WORKDIR/winecx.deb"          "$DESCARGAS/winecx.deb"
ln -sf "$WORKDIR/MSO365"              "$DESCARGAS/MSO365"
ln -sf "$WORKDIR/$INSTALLER_FILE"     "$DESCARGAS/$INSTALLER_FILE"

# Create symlinks for fallback zips if they exist
[ -f "$WORKDIR/$CACHY_ZIP" ] && ln -sf "$WORKDIR/$CACHY_ZIP" "$DESCARGAS/$CACHY_ZIP" 2>/dev/null || true
[ -f "$WORKDIR/$ARCH_ZIP" ] && ln -sf "$WORKDIR/$ARCH_ZIP" "$DESCARGAS/$ARCH_ZIP" 2>/dev/null || true
[ -f "$WORKDIR/$MANJARO_ZIP" ] && ln -sf "$WORKDIR/$MANJARO_ZIP" "$DESCARGAS/$MANJARO_ZIP" 2>/dev/null || true

log "Ejecutando instalador principal ($FAMILY)"
OFFICE365_WORKDIR="$WORKDIR" bash "$WORKDIR/$INSTALLER_FILE"

# ----- cleanup -----
if [ "$KEEP_CACHE" = "0" ] && [ "$OFFICE_VER" = "365" ]; then
  log "Limpiando cache. Usa --keep-cache para conservar."
  rm -rf "$WORKDIR/MSO365" "$WORKDIR"/MSO365.zip "$WORKDIR"/MSO365.zip.part*.bin
fi

ok "Instalación completa. Busca 'Word 365', 'Excel 365', etc. en tu menú de aplicaciones."
echo

# ----- show appropriate uninstaller -----
case "$FAMILY:$OFFICE_VER" in
   debian:*)        echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall.sh | bash" ;;
   arch:*|manjaro:*|cachyos:*) echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall-arch.sh | bash" ;;
   fedora:*)        echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall-office2016-fedora.sh | bash" ;;
esac
