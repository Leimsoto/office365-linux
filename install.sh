#!/usr/bin/env bash
# install.sh — Office 365 (WineCX) installer for Debian-based distros
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/install.sh | bash -s -- --yes
#
# Flags:
#   --yes / -y      Non-interactive, assume yes
#   --keep-cache    Don't remove downloaded archives after install
#   --tag=vX.Y.Z    Pin a specific release tag (default: latest)
#   --no-verify     Skip SHA256 verification (NOT recommended)

set -euo pipefail
IFS=$'\n\t'

# ----- config -----
REPO_OWNER="Leimsoto"
REPO_NAME="office365-debian"
DEFAULT_TAG="v1.0.0"
INSTALLER_BRANCH="${OFFICE365_INSTALLER_BRANCH:-main}"
WORKDIR="${OFFICE365_WORKDIR:-$HOME/.cache/office365-debian}"
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
for arg in "$@"; do
  case "$arg" in
    -y|--yes)        ASSUME_YES=1 ;;
    --keep-cache)    KEEP_CACHE=1 ;;
    --no-verify)     DO_VERIFY=0 ;;
    --tag=*)         TAG="${arg#--tag=}" ;;
    -h|--help)
      sed -n '2,12p' "$0"
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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Instalando dependencia: $1"
    sudo apt-get install -y "$2" || die "No se pudo instalar $2"
  }
}

# ----- banner -----
cat <<'BANNER'
==========================================================
   Microsoft Office 365 on Debian/Ubuntu (WineCX)
   Repo: https://github.com/Leimsoto/office365-debian
   License: GPL-3.0
==========================================================
BANNER

# ----- preflight -----
[ "$(id -u)" -ne 0 ] || die "No ejecutes como root. El script usa sudo cuando lo necesita."
. /etc/os-release 2>/dev/null || die "No se pudo leer /etc/os-release"
case "${ID_LIKE:-$ID}" in
  *debian*|*ubuntu*) ok "Distro compatible: $PRETTY_NAME" ;;
  *) warn "Distro no es Debian-based ($PRETTY_NAME). Continúa bajo tu propio riesgo." ;;
esac

if ! confirm "Se descargarán ~2.3 GB de assets y se modificará el sistema (apt, /opt/winecx, /usr/share/applications). ¿Continuar?"; then
  die "Cancelado por el usuario."
fi

# ----- ensure tools -----
sudo -v || die "sudo requerido."
need_cmd curl curl
need_cmd unzip unzip
need_cmd sha256sum coreutils

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----- download assets -----
BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}"
log "Tag: $TAG"
log "Destino: $WORKDIR"

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

# ----- run installer -----
log "Extrayendo MSO365.zip"
rm -rf MSO365
unzip -q -o MSO365.zip

# Place winecx.deb where the installer expects it (alongside the extracted folder content).
cp -f winecx.deb MSO365/winecx.deb

# Fetch the installer script from the chosen branch (main = latest fixes).
# Override with OFFICE365_INSTALLER_BRANCH=vX.Y.Z for reproducibility against a tag.
INSTALLER_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${INSTALLER_BRANCH}/scripts/instalar-office365-winecx.sh"
log "Descargando script principal: $INSTALLER_RAW"
curl -fL -o instalar-office365-winecx.sh "$INSTALLER_RAW"
chmod +x instalar-office365-winecx.sh

# The legacy script expects everything under $HOME/Descargas. Re-locate symlinks.
DESCARGAS="$HOME/Descargas"
mkdir -p "$DESCARGAS"
ln -sf "$WORKDIR/MSO365.zip"             "$DESCARGAS/MSO365.zip"
ln -sf "$WORKDIR/winecx.deb"             "$DESCARGAS/winecx.deb"
ln -sf "$WORKDIR/MSO365"                 "$DESCARGAS/MSO365"
ln -sf "$WORKDIR/instalar-office365-winecx.sh" "$DESCARGAS/instalar-office365-winecx.sh"

log "Ejecutando instalador principal"
bash "$WORKDIR/instalar-office365-winecx.sh"

# ----- cleanup -----
if [ "$KEEP_CACHE" = "0" ]; then
  log "Limpiando cache (~2.3 GB). Usa --keep-cache para conservar."
  rm -rf "$WORKDIR/MSO365" "$WORKDIR"/MSO365.zip "$WORKDIR"/MSO365.zip.part*.bin
fi

ok "Instalación completa. Busca 'Word 365', 'Excel 365', etc. en tu menú de aplicaciones."
echo
echo "Para desinstalar: curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/scripts/uninstall.sh | bash"
