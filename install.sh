#!/usr/bin/env bash
# install.sh — Office 365 (WineCX) installer for Debian/Ubuntu AND Arch/Artix
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash -s -- --yes
#
# Flags:
#   --yes / -y      Non-interactive, assume yes
#   --keep-cache    Don't remove downloaded archives after install
#   --tag=vX.Y.Z    Pin a specific release tag (default: v1.0.0 for assets)
#   --no-verify     Skip SHA256 verification (NOT recommended)
#   --family=auto   Force distro family: auto|debian|arch|cachyos|fedora
#   --office=365    Office 365 (default, no disponible en Fedora)
#   --office=2016   Office 2016 (solo Fedora, requiere ISO manual)

set -euo pipefail
IFS=$'\n\t'

# ----- config -----
REPO_OWNER="Leimsoto"
REPO_NAME="office365-linux"
DEFAULT_TAG="v1.0.0"
INSTALLER_BRANCH="${OFFICE365_INSTALLER_BRANCH:-main}"
WORKDIR="${OFFICE365_WORKDIR:-$HOME/.cache/office365-linux}"
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

# ----- args -----
ASSUME_YES=0
KEEP_CACHE=0
TAG="$DEFAULT_TAG"
DO_VERIFY=1
FAMILY_OVERRIDE="auto"
OFFICE_VER="365"
for arg in "$@"; do
  case "$arg" in
    -y|--yes)        ASSUME_YES=1 ;;
    --keep-cache)    KEEP_CACHE=1 ;;
    --no-verify)     DO_VERIFY=0 ;;
    --tag=*)         TAG="${arg#--tag=}" ;;
    --family=*)      FAMILY_OVERRIDE="${arg#--family=}" ;;
    --office=*)      OFFICE_VER="${arg#--office=}" ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ----- helpers -----
c_red()  { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn()  { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw()  { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu()  { printf '\033[1;34m%s\033[0m' "$*"; }
log()    { echo "$(c_blu '[INFO]')  $*"; }
ok()     { echo "$(c_grn '[ OK ]')  $*"; }
warn()   { echo "$(c_ylw '[WARN]')  $*"; }
die()    { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  local prompt="${1:-Continuar?} [y/N]: "
  read -r -p "$prompt" ans </dev/tty || die "TTY no disponible. Usar --yes."
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ----- banner -----
cat <<'BANNER'
==========================================================
   Microsoft Office 365 (WineCX) — Linux installer
   Repo: https://github.com/Leimsoto/office365-linux
   License: GPL-3.0
==========================================================
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

FAMILY="$FAMILY_OVERRIDE"
[ "$FAMILY" = "auto" ] && FAMILY="$(detect_family)"

case "$FAMILY" in
  debian)  ok "Distro: $PRETTY_NAME (familia: Debian/Ubuntu)" ;;
  arch)    ok "Distro: $PRETTY_NAME (familia: Arch/Artix)" ;;
  cachyos) ok "Distro: $PRETTY_NAME (familia: CachyOS — build especial)" ;;
  fedora)  ok "Distro: $PRETTY_NAME (familia: Fedora/RHEL)" ;;
  *)       die "Distro no soportada: $PRETTY_NAME. Forzar con --family=debian|arch|cachyos|fedora." ;;
esac

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
  cachyos:365)
    INSTALLER_FILE="instalar-office365-winecx-cachyos.sh"
    DL_SIZE_MSG="~2.3 GB de assets + ~1 GB WineCX CachyOS build"
    SYS_CHANGES="pacman, /opt/winecx (compile-time make install), /usr/share/applications"
    ;;
  fedora:2016)
    INSTALLER_FILE="instalar-office2016-fedora.sh"
    DL_SIZE_MSG="~432 MB Wine Fedora + ~367 MB requerimientos. ISO Office 2016 + Activador deben estar en \$HOME/Descargas"
    SYS_CHANGES="dnf (muchas -devel), /opt/winecx, /opt/wine/launchers, /usr/share/applications, RPM Fusion, ~/.office2016 prefix"
    ;;
  fedora:*)
    die "Office 365 no está disponible en Fedora. Usa --office=2016 para Fedora."
    ;;
  *:*)
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
  arch|cachyos)
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
log "Tag: $TAG"
log "Destino: $WORKDIR"

if [ "$OFFICE_VER" = "365" ]; then
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
else
  log "Office 2016 — assets serán descargados por el installer (winecx-fedora.zip + Requerimientos + Fuentes)"
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

log "Ejecutando instalador principal ($FAMILY)"
OFFICE365_WORKDIR="$WORKDIR" bash "$WORKDIR/$INSTALLER_FILE"

# ----- cleanup -----
if [ "$KEEP_CACHE" = "0" ] && [ "$OFFICE_VER" = "365" ]; then
  log "Limpiando cache. Usa --keep-cache para conservar."
  rm -rf "$WORKDIR/MSO365" "$WORKDIR"/MSO365.zip "$WORKDIR"/MSO365.zip.part*.bin
fi

ok "Instalación completa. Busca 'Word 365', 'Excel 365', etc. en tu menú de aplicaciones."
echo
case "$FAMILY:$OFFICE_VER" in
   debian:*)        echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall.sh | bash" ;;
   arch:*|cachyos:*) echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall-arch.sh | bash" ;;
   fedora:*)        echo "Desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall-office2016-fedora.sh | bash" ;;
esac
