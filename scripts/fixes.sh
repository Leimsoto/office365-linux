#!/bin/bash
# fixes.sh — Menú interactivo de reparación y mantenimiento para
# Office 365 (WineCX) en Debian/Ubuntu/Arch/Artix/CachyOS.
# Para Fedora se usa Office 2016 (ver scripts específicos).
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/fixes.sh | bash
#   (también puede invocarse con un número directo: bash fixes.sh 2)

set -euo pipefail

# ---------- detección distro / familia ----------
. /etc/os-release 2>/dev/null || { echo "ERROR: /etc/os-release no encontrado"; exit 1; }

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
    *)
      case "${ID_LIKE:-}" in
        *debian*|*ubuntu*) echo "debian"; return ;;
        *arch*)            echo "arch"; return ;;
        *)                 echo "unknown"; return ;;
      esac
      ;;
  esac
}

FAMILY="$(detect_family)"

# ---------- check for Office 365 or 2016 ----------
PREFIX="$HOME/.Microsoft_Office_365"
FONTDIR_SYS="/usr/share/fonts/Windows"
FONTDIR_PREFIX="$PREFIX/drive_c/windows/Fonts"

if [ ! -d "$PREFIX" ] && [ -d "$HOME/.office2016" ]; then
  cat <<'EOF'
==========================================================
    Office 2016 detectado (Fedora)
    Este script es para Office 365 (Debian/Arch/Manjaro/CachyOS).
    Para Office 2016 en Fedora, los fixes se hacen manualmente:
    - Prefix: ~/.office2016
    - Wine: /opt/winecx
    - Launchers: /opt/wine/launchers
==========================================================
EOF
  exit 0
fi

if [ ! -d "$PREFIX" ]; then
  die "No se encontró Office 365 instalado (~/.Microsoft_Office_365 no existe)"
fi

if [ ! -d "$PREFIX" ]; then
  die "No se encontró Office 365 instalado (~/.Microsoft_Office_365 no existe)"
fi

# ---------- helpers ----------
c_red()  { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn()  { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw()  { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu()  { printf '\033[1;34m%s\033[0m' "$*"; }
log()    { echo "$(c_blu '[INFO]')  $*"; }
ok()     { echo "$(c_grn '[ OK ]')  $*"; }
warn()   { echo "$(c_ylw '[WARN]')  $*"; }
die()    { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

pkg_install() {
  case "$FAMILY" in
    debian) sudo apt-get install -y "$@" 2>&1 | tail -3 || true ;;
    arch)   sudo pacman -S --noconfirm --needed "$@" 2>&1 | tail -3 || true ;;
    *)      warn "Distro $FAMILY no soportada para instalación de paquetes" ;;
  esac
}

ensure_dirs() {
  sudo mkdir -p "$FONTDIR_SYS"
  [ -d "$PREFIX" ] && mkdir -p "$FONTDIR_PREFIX" || true
}

# ============================================================
# 1) Reparar pacman.conf (Artix / Arch)
# ============================================================
fix_pacman_artix() {
  [ "$ID" = "artix" ] || { warn "Solo aplica a Artix. Distro actual: $PRETTY_NAME"; return; }
  TS=$(date +%Y%m%d-%H%M%S)
  sudo cp /etc/pacman.conf "/etc/pacman.conf.preFix-$TS"
  log "Backup: /etc/pacman.conf.preFix-$TS"

  # Architecture
  if ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
    if grep -qE '^#\s*Architecture\s*=' /etc/pacman.conf; then
      sudo sed -i 's/^#\s*\(Architecture\s*=.*\)/\1/' /etc/pacman.conf
    else
      sudo sed -i '/^\[options\]/a Architecture = auto' /etc/pacman.conf
    fi
  fi

  # Si falta [options] o nativos, reconstruir base
  if ! grep -qE '^\[options\]' /etc/pacman.conf || ! grep -qE '^\[(system|world|galaxy|lib32)\]' /etc/pacman.conf; then
    sudo tee /etc/pacman.conf >/dev/null <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[system]
Include = /etc/pacman.d/mirrorlist

[world]
Include = /etc/pacman.d/mirrorlist

[galaxy]
Include = /etc/pacman.d/mirrorlist

[lib32]
Include = /etc/pacman.d/mirrorlist
EOF
  fi

  sudo pacman -Syy --noconfirm
  sudo pacman -S --noconfirm --needed artix-archlinux-support

  # Strip [multilib]/[extra] mal apuntados y reinyectar
  TMP=$(mktemp)
  sudo awk '
    BEGIN { skip = 0 }
    /^\[multilib\]/ { skip = 1; next }
    /^\[extra\]/    { skip = 1; next }
    /^\[/           { skip = 0 }
    !skip           { print }
  ' /etc/pacman.conf > "$TMP"
  sudo mv "$TMP" /etc/pacman.conf
  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

  # chaotic-aur si los archivos siguen
  if [ -f /etc/pacman.d/chaotic-mirrorlist ] && ! grep -qE '^\[chaotic-aur\]' /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  fi

  sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db
  sudo pacman -Syy --noconfirm
  ok "pacman.conf reparado"
}

# ============================================================
# 2) Instalar fonts extra
# ============================================================
install_extra_fonts() {
  log "Instalando fonts metric-compat desde repos del sistema"
  case "$FAMILY" in
    debian)
      pkg_install \
        fonts-crosextra-carlito \
        fonts-crosextra-caladea \
        fonts-liberation \
        fonts-liberation2 \
        fonts-noto \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        fonts-dejavu \
        fonts-firacode \
        fonts-jetbrains-mono \
        fonts-cantarell \
        fonts-roboto \
        fonts-hack \
        fonts-inconsolata \
        fonts-open-sans
      ;;
    arch)
      pkg_install \
        ttf-carlito \
        ttf-caladea \
        ttf-liberation \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        ttf-dejavu \
        ttf-fira-code \
        ttf-jetbrains-mono \
        cantarell-fonts \
        ttf-roboto \
        ttf-hack \
        ttf-inconsolata \
        ttf-opensans
      ;;
  esac

  log "Instalando fonts Microsoft open source (GitHub)"
  ensure_dirs
  TMPFONTS=$(mktemp -d)
  cd "$TMPFONTS"

  # Aptos (Microsoft 2023, default Office 365)
  log "  Aptos family"
  for f in Aptos.ttf Aptos-Bold.ttf Aptos-Italic.ttf Aptos-BoldItalic.ttf \
           Aptos-Light.ttf Aptos-LightItalic.ttf \
           Aptos-SemiBold.ttf Aptos-SemiBoldItalic.ttf \
           Aptos-ExtraBold.ttf Aptos-ExtraBoldItalic.ttf \
           Aptos-Black.ttf Aptos-BlackItalic.ttf \
           Aptos-Display.ttf Aptos-DisplayBold.ttf Aptos-DisplayItalic.ttf \
           Aptos-Mono.ttf Aptos-Mono-Bold.ttf \
           Aptos-Serif.ttf Aptos-Serif-Bold.ttf Aptos-Serif-Italic.ttf Aptos-Serif-BoldItalic.ttf; do
    curl -fL --silent -o "$f" "https://github.com/microsoft/Aptos-fonts/raw/main/$f" 2>/dev/null || true
  done

  # Cascadia Code (Microsoft, OFL)
  log "  Cascadia Code"
  curl -fL --silent -o cascadia.zip \
    "https://github.com/microsoft/cascadia-code/releases/download/v2407.24/CascadiaCode-2407.24.zip" 2>/dev/null && \
    unzip -qo cascadia.zip -d cascadia 2>/dev/null && \
    cp -f cascadia/ttf/*.ttf . 2>/dev/null || true

  # Selawik (Microsoft, Segoe UI metric-compat)
  log "  Selawik"
  for f in selawk.ttf selawkb.ttf selawkl.ttf selawksb.ttf selawksl.ttf; do
    curl -fL --silent -o "$f" "https://github.com/microsoft/Selawik/raw/master/fonts/TTF/$f" 2>/dev/null || true
  done

  # Copiar al sistema + prefix
  COUNT=$(ls *.ttf 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    sudo cp -f *.ttf "$FONTDIR_SYS/" 2>/dev/null || true
    [ -d "$FONTDIR_PREFIX" ] && cp -f *.ttf "$FONTDIR_PREFIX/" 2>/dev/null || true
    ok "Copiadas $COUNT fonts Microsoft open source"
  else
    warn "No se descargaron fonts Microsoft (offline o repos cambiaron)"
  fi

  cd - >/dev/null
  rm -rf "$TMPFONTS"

  log "Refrescando cache fontconfig"
  sudo fc-cache -f >/dev/null 2>&1 || true
  fc-cache -f "$FONTDIR_PREFIX" >/dev/null 2>&1 || true

  log "Re-registrando fonts en el registry de wine"
  if [ -d "$PREFIX" ] && [ -x /opt/winecx/bin/wine ]; then
    LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
    WINEPREFIX="$PREFIX" bash -c '
      FONTDIR="$WINEPREFIX/drive_c/windows/Fonts"
      REGFILE="$WINEPREFIX/allfonts.reg"
      {
        echo "REGEDIT4"
        echo ""
        echo "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]"
        for f in "$FONTDIR"/*.ttf "$FONTDIR"/*.TTF "$FONTDIR"/*.otf "$FONTDIR"/*.OTF "$FONTDIR"/*.ttc "$FONTDIR"/*.TTC; do
          [ -e "$f" ] || continue
          base=$(basename "$f")
          name="${base%.*}"
          label=$(echo "$name" | sed "s/_/ /g" | sed "s/Regular//g")
          echo "\"$label (TrueType)\"=\"${base}\""
        done
      } > "$REGFILE"
      /opt/winecx/bin/wine regedit "$REGFILE" >/dev/null 2>&1 || true
    '
  fi
  ok "Fonts instaladas"
}

# ============================================================
# 3) Matar procesos Office / Wine
# ============================================================
kill_office() {
  log "Matando procesos Office/Wine"
  pkill -KILL -f '/opt/winecx' 2>/dev/null || true
  pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true
  [ -d "$PREFIX" ] && [ -x /opt/winecx/bin/wineserver ] && \
    WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
  ok "Procesos terminados"
}

# ============================================================
# 4) Re-inicializar prefix wine
# ============================================================
reinit_prefix() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  log "wineboot -u con LD_LIBRARY_PATH bundle"
  LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
    WINEPREFIX="$PREFIX" /opt/winecx/bin/wine wineboot -u || true
  LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
    WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k || true
  ok "Prefix re-inicializado"
}

# ============================================================
# 5) Verificar estado instalación
# ============================================================
check_status() {
  echo ""
  echo "=== Estado instalación Office 365 ==="
  echo -n "  Prefix ($PREFIX): "
  [ -d "$PREFIX" ] && echo "$(c_grn 'existe')" || echo "$(c_red 'falta')"
  echo -n "  WineCX (/opt/winecx): "
  [ -d /opt/winecx ] && echo "$(c_grn 'existe')" || echo "$(c_red 'falta')"
  echo -n "  Launchers (/opt/winecx/launchers): "
  [ -d /opt/winecx/launchers ] && echo "$(c_grn 'existe') ($(ls /opt/winecx/launchers/*.sh 2>/dev/null | wc -l) scripts)" || echo "$(c_red 'falta')"
  echo -n "  Desktop entries: "
  COUNT=$(ls /usr/share/applications/*365.desktop 2>/dev/null | wc -l)
  [ "$COUNT" -gt 0 ] && echo "$(c_grn "$COUNT entradas")" || echo "$(c_red 'faltan')"
  echo -n "  Fonts en prefix: "
  if [ -d "$FONTDIR_PREFIX" ]; then
    echo "$(c_grn "$(ls "$FONTDIR_PREFIX" 2>/dev/null | wc -l) archivos")"
  else
    echo "$(c_red 'falta')"
  fi
  echo -n "  Fonts globales ($FONTDIR_SYS): "
  if [ -d "$FONTDIR_SYS" ]; then
    echo "$(c_grn "$(ls "$FONTDIR_SYS" 2>/dev/null | wc -l) archivos")"
  else
    echo "$(c_red 'falta')"
  fi
  echo -n "  WineCX runtime: "
  if [ -x /opt/winecx/bin/wine ]; then
    VER=$(LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" /opt/winecx/bin/wine --version 2>&1 || echo "ERROR")
    echo "$(c_grn "$VER")"
  else
    echo "$(c_red 'falta')"
  fi
  echo ""
}

# ============================================================
# 6) Limpiar cache
# ============================================================
clean_cache() {
  log "Borrando ~/.cache/office365-linux"
  rm -rf "$HOME/.cache/office365-linux"
  ok "Cache borrado"
}

# ============================================================
# 7) Desinstalar todo
# ============================================================
uninstall_all() {
  warn "Esta acción borrará Office 365 + WineCX + launchers + íconos."
  read -r -p "¿Confirmas? [y/N]: " ans </dev/tty
  [[ ! "$ans" =~ ^[Yy]$ ]] && { log "Cancelado"; return; }
  # Smart uninstaller auto-detects distro and Office version
  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/uninstall.sh | bash
}

# ============================================================
# 10) Wine virtual desktop (fix ventana transparente en KDE/KWin/Wayland)
# ============================================================
enable_virtual_desktop() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  LDP="LD_LIBRARY_PATH=/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine"
  WINE=/opt/winecx/bin/wine

  echo "Resoluciones comunes:"
  echo "  1) 1920x1080"
  echo "  2) 1600x900   (default)"
  echo "  3) 1366x768"
  echo "  4) 1280x720"
  echo "  5) Personalizada"
  read -r -p "Opción [2]: " ans </dev/tty
  case "${ans:-2}" in
    1) RES="1920x1080" ;;
    2|"") RES="1600x900" ;;
    3) RES="1366x768" ;;
    4) RES="1280x720" ;;
    5) read -r -p "Resolución (ej. 1440x900): " RES </dev/tty ;;
    *) RES="1600x900" ;;
  esac
  log "Resolución: $RES"

  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Wine\\Explorer" /v Desktop /t REG_SZ /d "Office" /f 2>/dev/null

  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Office /t REG_SZ /d "$RES" /f 2>/dev/null

  env $LDP WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
  ok "Wine virtual desktop activado ($RES). Lanza Word/Excel."
}

disable_virtual_desktop() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  LDP="LD_LIBRARY_PATH=/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine"
  WINE=/opt/winecx/bin/wine

  env $LDP WINEPREFIX="$PREFIX" $WINE reg delete \
    "HKCU\\Software\\Wine\\Explorer" /v Desktop /f 2>/dev/null || true
  env $LDP WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
  ok "Wine virtual desktop desactivado (modo nativo de ventana)"
}

# ============================================================
# 12) Reparar pantalla de inicio de sesión en blanco (WAM/ADAL)
# ============================================================
fix_blank_login() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  LDP="LD_LIBRARY_PATH=/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine"
  WINE=/opt/winecx/bin/wine

  log "Desactivando WAM (Web Account Manager) y forzando ADAL clásico..."

  # Desactivar WAM para Azure AD
  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v DisableAADWAM /t REG_DWORD /d 1 /f 2>/dev/null || true

  # Desactivar WAM override
  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v DisableADALatopWAMOverride /t REG_DWORD /d 1 /f 2>/dev/null || true

  # Habilitar ADAL (Modern Auth clásico compatible con Wine)
  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v EnableADAL /t REG_DWORD /d 1 /f 2>/dev/null || true

  # Opcional: Desactivar aceleración gráfica para la ventana de login
  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Graphics" /v DisableHardwareAcceleration /t REG_DWORD /d 1 /f 2>/dev/null || true

  # Limpiar credenciales de Office
  log "Limpiando posibles archivos de licencia corruptos..."
  rm -f "$PREFIX/drive_c/users/"*/AppData/Local/Microsoft/Office/16.0/Licensing/*.lic 2>/dev/null || true

  env $LDP WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
  ok "Configuración de inicio de sesión reparada. Abre Word/Excel e intenta iniciar sesión nuevamente."
}

# ============================================================
# 9) Reparar cache de fonts wine (cuelgues en dropdown de fonts)
# ============================================================
repair_font_cache() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  log "Matando wineserver"
  WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true

  log "Borrando font caches en el prefix"
  rm -rf "$PREFIX/drive_c/users/"*/AppData/Local/Microsoft/Windows/Fonts 2>/dev/null || true
  rm -rf "$PREFIX/drive_c/users/"*/AppData/Roaming/wine/fontcache 2>/dev/null || true

  log "Borrando fontconfig cache del usuario"
  rm -rf "$HOME/.cache/fontconfig"

  # Variable fonts son los culpables típicos: wine no parsea VF bien.
  # Identificarlos y removerlos.
  log "Buscando Variable Fonts (causa común de cuelgues)"
  VF_FOUND=()
  for d in "$FONTDIR_SYS" "$FONTDIR_PREFIX"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do
      VF_FOUND+=("$f")
    done < <(find "$d" -maxdepth 1 -iname '*VariableFont*' -o -iname '*VF.ttf' 2>/dev/null)
  done

  # Aptos.ttf (la base sin sufijo) suele ser la versión variable
  for d in "$FONTDIR_SYS" "$FONTDIR_PREFIX"; do
    [ -f "$d/Aptos.ttf" ] && VF_FOUND+=("$d/Aptos.ttf")
  done

  if [ ${#VF_FOUND[@]} -gt 0 ]; then
    echo "Variable Fonts detectados (potenciales culpables):"
    printf '  - %s\n' "${VF_FOUND[@]}"
    read -r -p "¿Borrarlas? [y/N]: " ans </dev/tty
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      for f in "${VF_FOUND[@]}"; do
        sudo rm -f "$f"
      done
      ok "Variable Fonts removidas"
    fi
  else
    log "No se encontraron Variable Fonts"
  fi

  log "Re-construyendo cache fontconfig"
  sudo fc-cache -f >/dev/null 2>&1 || true
  fc-cache -f >/dev/null 2>&1 || true

  log "wineboot -u para re-registrar fonts"
  LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
    WINEPREFIX="$PREFIX" /opt/winecx/bin/wine wineboot -u 2>/dev/null || true
  LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
    WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true

  ok "Font cache reparado. Re-lanza Word/Excel."
}

# ============================================================
# 13) Instalar paquete de idioma adicional (zh-cn, en-us, etc.)
# ============================================================
install_language_pack() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  LDP="LD_LIBRARY_PATH=/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine"
  WINE=/opt/winecx/bin/wine

  echo "Selecciona el idioma que deseas instalar:"
  echo "  1) Chino Simplificado (zh-cn)"
  echo "  2) Inglés (en-us)"
  echo "  3) Portugués Brasileño (pt-br)"
  echo "  4) Francés (fr-fr)"
  echo "  5) Alemán (de-de)"
  echo "  6) Otro (introducir código, ej: it-it)"
  read -r -p "Opción [1-6]: " lang_opt </dev/tty

  local LANG_CODE=""
  case "$lang_opt" in
    1) LANG_CODE="zh-cn" ;;
    2) LANG_CODE="en-us" ;;
    3) LANG_CODE="pt-br" ;;
    4) LANG_CODE="fr-fr" ;;
    5) LANG_CODE="de-de" ;;
    6) read -r -p "Introduce el código del idioma (ej. ru-ru, ja-jp): " LANG_CODE </dev/tty ;;
    *) warn "Opción inválida"; return ;;
  esac

  [ -n "$LANG_CODE" ] || { warn "Código de idioma no válido"; return; }

  # 1) Verificar e instalar fuentes específicas para evitar caracteres rotos (tofu)
  if [[ "$LANG_CODE" == "zh-cn" || "$LANG_CODE" == "zh-tw" || "$LANG_CODE" == "ja-jp" || "$LANG_CODE" == "ko-kr" ]]; then
    log "Idioma CJK detectado. Verificando e instalando fuentes CJK en el sistema..."
    case "$FAMILY" in
      debian)
        pkg_install fonts-noto-cjk fonts-noto-cjk-extra || true
        ;;
      arch|cachyos|manjaro)
        pkg_install noto-fonts-cjk || true
        ;;
    esac
  fi

  # 2) Descargar instalador web de Microsoft (dynamic bootstrapper)
  local EXE_NAME="OfficeSetup_${LANG_CODE}.exe"
  local DL_URL="https://c2rsetup.officeapps.live.com/c2r/download.aspx?ProductreleaseID=LanguagePack&language=${LANG_CODE}&platform=x86"
  local DL_PATH="/tmp/${EXE_NAME}"

  log "Descargando instalador de idioma '${LANG_CODE}' desde Microsoft CDN..."
  if ! curl -fL --retry 3 --progress-bar -o "$DL_PATH" "$DL_URL"; then
    die "No se pudo descargar el paquete de idioma desde: $DL_URL"
  fi

  # 3) Ejecutar instalador Click-to-Run en el prefijo
  log "Abriendo instalador de Microsoft. Sigue los pasos en pantalla..."
  env $LDP WINEPREFIX="$PREFIX" $WINE "$DL_PATH" || true

  # 4) Limpieza del instalador temporal
  rm -f "$DL_PATH"

  # 5) Aplicar fixes de registro para reparar el login y desactivar WAM
  log "Re-aplicando configuraciones de seguridad e inicio de sesión..."
  fix_blank_login

  # 6) Reconstruir cachés de fuentes para evitar cuelgues
  log "Refrescando bases de fuentes de Wine..."
  env $LDP WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
  rm -rf "$PREFIX/drive_c/users/"*/AppData/Local/Microsoft/Windows/Fonts 2>/dev/null || true
  rm -rf "$PREFIX/drive_c/users/"*/AppData/Roaming/wine/fontcache 2>/dev/null || true
  sudo fc-cache -f >/dev/null 2>&1 || true
  fc-cache -f >/dev/null 2>&1 || true

  ok "Instalación del paquete de idioma '${LANG_CODE}' completada."
}

# ============================================================
# 8) Re-instalación limpia
# ============================================================
reinstall() {
  warn "Esta acción desinstala y re-instala Office 365."
  read -r -p "¿Confirmas? [y/N]: " ans </dev/tty
  [[ ! "$ans" =~ ^[Yy]$ ]] && { log "Cancelado"; return; }
  uninstall_all
  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash
}

# ============================================================
# 14) Desactivar cloud fonts (fix desplegable de fuentes congelado)
# ============================================================
disable_cloud_fonts() {
  [ -d "$PREFIX" ] || die "Prefix $PREFIX no existe"
  LDP="LD_LIBRARY_PATH=/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine"
  WINE=/opt/winecx/bin/wine

  cat <<'EOF'
  El desplegable de fuentes se congela por las "cloud fonts":
  el gallery de Office se bloquea en NtGdiSelectFont al pintarlas
  (probado en Word y Excel con el mismo backtrace).
  Este fix desactiva las experiencias conectadas que descargan
  contenido en línea (incluye cloud fonts). Tus documentos y las
  fuentes instaladas siguen funcionando igual.
EOF
  warn "Se cerrará Word/Excel para aplicar el cambio."
  read -r -p "¿Continuar? [y/N]: " ans </dev/tty
  [[ ! "$ans" =~ ^[Yy]$ ]] && { log "Cancelado"; return; }

  log "Desactivando descarga de contenido en línea (cloud fonts)..."
  env $LDP WINEPREFIX="$PREFIX" $WINE reg add \
    "HKCU\\Software\\Policies\\Microsoft\\Office\\16.0\\common\\privacy" /v DownloadContentDisabled /t REG_DWORD /d 2 /f 2>/dev/null || \
    die "No se pudo escribir el registro"

  log "Verificando valor..."
  if env $LDP WINEPREFIX="$PREFIX" $WINE reg query \
    "HKCU\\Software\\Policies\\Microsoft\\Office\\16.0\\common\\privacy" /v DownloadContentDisabled 2>/dev/null | grep -qi 'DownloadContentDisabled'; then
    ok "Valor verificado en el registro"
  else
    warn "No se pudo verificar (re-lanza y prueba el desplegable igual)"
  fi

  log "Apagado graceful para flushear el registro a disco (kill -9 lo perdería)..."
  env $LDP WINEPREFIX="$PREFIX" $WINE wineboot -e 2>/dev/null || true
  env $LDP WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true

  ok "Listo. Re-lanza Word/Excel: sin iconos de nube, el desplegable ya no se congela."
  warn "Efecto colateral: también desactiva plantillas en línea y otras funciones conectadas."
  log "Revertir: reg delete 'HKCU\\Software\\Policies\\Microsoft\\Office\\16.0\\common\\privacy' /v DownloadContentDisabled /f"
}

# ============================================================
# MENU
# ============================================================
menu() {
  cat <<EOF

==========================================================
   Office 365 (WineCX) — Menú de reparación / fixes
   Distro: $PRETTY_NAME (familia: $FAMILY)
==========================================================

  1) Reparar /etc/pacman.conf (solo Artix)
  2) Instalar fonts adicionales (Aptos, Cascadia, Selawik, Carlito, Liberation, Noto CJK, etc.)
  3) Matar procesos Office/Wine colgados
  4) Re-inicializar prefix wine (wineboot -u)
  5) Verificar estado instalación
  6) Limpiar cache de descarga
  7) Desinstalar todo
  8) Re-instalación limpia (desinstala + instala)
  9) Reparar cache de fonts wine (cuelgues en dropdown de fonts)
 10) Activar Wine virtual desktop (fix ventana transparente KDE/KWin/Wayland)
 11) Desactivar Wine virtual desktop (volver a ventana nativa)
 12) Reparar pantalla de inicio de sesión en blanco (Desactivar WAM / Forzar ADAL)
  13) Instalar paquete de idioma adicional (zh-cn, en-us, pt-br, etc.)
  14) Desactivar cloud fonts (fix desplegable de fuentes congelado)
   q) Salir

EOF
  read -r -p "Opción: " choice </dev/tty
  case "$choice" in
    1) fix_pacman_artix ;;
    2) install_extra_fonts ;;
    3) kill_office ;;
    4) reinit_prefix ;;
    5) check_status ;;
    6) clean_cache ;;
    7) uninstall_all ;;
    8) reinstall ;;
    9) repair_font_cache ;;
    10) enable_virtual_desktop ;;
    11) disable_virtual_desktop ;;
    12) fix_blank_login ;;
    13) install_language_pack ;;
    14) disable_cloud_fonts ;;
    q|Q) exit 0 ;;
    *) warn "Opción inválida" ;;
  esac
}

# Modo directo: bash fixes.sh 2 ejecuta opción 2 y sale
if [ $# -gt 0 ]; then
  case "$1" in
    1) fix_pacman_artix ;;
    2) install_extra_fonts ;;
    3) kill_office ;;
    4) reinit_prefix ;;
    5) check_status ;;
    6) clean_cache ;;
    7) uninstall_all ;;
    8) reinstall ;;
    9) repair_font_cache ;;
    10) enable_virtual_desktop ;;
    11) disable_virtual_desktop ;;
    12) fix_blank_login ;;
    13) install_language_pack ;;
    14) disable_cloud_fonts ;;
    *) die "Opción inválida: $1 (válidas: 1-14)" ;;
  esac
  exit 0
fi

# Modo interactivo: loop hasta q
while true; do
  menu
done

