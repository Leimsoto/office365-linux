#!/bin/bash
# Instalador Office 365 + WineCX para Arch Linux y derivadas (Artix, Manjaro,
# EndeavourOS, CachyOS, Garuda, ArcoLinux). Soporta init systems systemd,
# runit, openrc y s6/dinit (autodetectado).
#
# Esperado: directorio MSO365/ desempaquetado y winecx.deb dentro, además del
# bundle arch-winecx-libs.tar.zst extraído a /opt/winecx por install.sh.
# Standalone OK desde $HOME/Descargas o invocado por install.sh.

set -euo pipefail

# Helpers (log/ok/warn/die). Definidos aquí porque este script se ejecuta en un
# bash hijo desde install.sh y no hereda las funciones del padre. También
# permite ejecución standalone desde $HOME/Descargas.
c_red() { printf '\033[1;31m%s\033[0m' "$*"; }
c_grn() { printf '\033[1;32m%s\033[0m' "$*"; }
c_ylw() { printf '\033[1;33m%s\033[0m' "$*"; }
c_blu() { printf '\033[1;34m%s\033[0m' "$*"; }
log()  { echo "$(c_blu '[INFO]')  $*"; }
ok()   { echo "$(c_grn '[ OK ]')  $*"; }
warn() { echo "$(c_ylw '[WARN]')  $*"; }
die()  { echo "$(c_red '[FAIL]')  $*" >&2; exit 1; }

echo "==============================================="
echo "  Office 365 - WineCX (Arch / Artix / Manjaro)"
echo "==============================================="

WORKDIR="${OFFICE365_WORKDIR:-$HOME/Descargas}"
cd "$WORKDIR"

# ---------------------------------------------------------
# Detección distro / init
# ---------------------------------------------------------
. /etc/os-release 2>/dev/null || { echo "ERROR: /etc/os-release no encontrado" >&2; exit 1; }

INIT_SYSTEM="$(cat /proc/1/comm 2>/dev/null || echo unknown)"
case "$INIT_SYSTEM" in
  systemd)        INIT="systemd" ;;
  runit*)         INIT="runit" ;;
  openrc*|init)   INIT="openrc" ;;
  s6-svscan)      INIT="s6" ;;
  dinit)          INIT="dinit" ;;
  *)              INIT="unknown" ;;
esac
echo ">> Distro: $PRETTY_NAME (init: $INIT)"

# ---------------------------------------------------------
# 1) MSO365.zip (extraer si no existe la carpeta)
# ---------------------------------------------------------
if [ ! -d "MSO365" ]; then
  [ -f "MSO365.zip" ] || { echo "ERROR: falta MSO365.zip en $WORKDIR" >&2; exit 1; }
  command -v unzip >/dev/null 2>&1 || sudo pacman -S --noconfirm --needed unzip
  unzip -o MSO365.zip
fi

cd "$WORKDIR/MSO365"

# ---------------------------------------------------------
# 2) Multilib en pacman.conf (idempotente, distingue Artix vs Arch)
# ---------------------------------------------------------
echo ">> Habilitando multilib y repos extra"

# Backup único de pacman.conf
[ -f /etc/pacman.conf.office365-bak ] || sudo cp /etc/pacman.conf /etc/pacman.conf.office365-bak

# Asegurar Architecture en [options]. mirrorlist-arch usa $arch.
if ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
  if grep -qE '^#\s*Architecture\s*=' /etc/pacman.conf; then
    sudo sed -i 's/^#\s*\(Architecture\s*=.*\)/\1/' /etc/pacman.conf
  else
    sudo sed -i '/^\[options\]/a Architecture = auto' /etc/pacman.conf
  fi
fi

if [ "$ID" = "artix" ]; then
  # Artix: multilib y extra viven en repos de Arch, NO en mirrorlist Artix.
  # Requiere artix-archlinux-support + mirrorlist-arch.
  sudo pacman -S --noconfirm --needed artix-archlinux-support || true

  # Detectar bloques [multilib]/[extra] mal configurados (apuntando a mirrorlist Artix)
  # y removerlos en bloque junto con sus directivas siguientes hasta el próximo [seccion].
  if grep -qE '^\[multilib\]' /etc/pacman.conf || grep -qE '^\[extra\]' /etc/pacman.conf; then
    NEEDS_REWRITE=0
    if grep -qE '^\[multilib\]' /etc/pacman.conf && \
       ! awk '/^\[multilib\]/,/^\[/{if($0 ~ /mirrorlist-arch/) print}' /etc/pacman.conf | grep -q mirrorlist-arch; then
      NEEDS_REWRITE=1
    fi
    if grep -qE '^\[extra\]' /etc/pacman.conf && \
       ! awk '/^\[extra\]/,/^\[/{if($0 ~ /mirrorlist-arch/) print}' /etc/pacman.conf | grep -q mirrorlist-arch; then
      NEEDS_REWRITE=1
    fi
    if [ "$NEEDS_REWRITE" = "1" ]; then
      echo ">> Reparando bloques [multilib]/[extra] mal configurados"
      # mktemp evita race condition con nombres predecibles en /tmp.
      PACMAN_TMP="$(mktemp /tmp/pacman.conf.XXXXXX)"
      sudo awk '
        BEGIN { skip = 0 }
        /^\[multilib\]/ { skip = 1; next }
        /^\[extra\]/    { skip = 1; next }
        /^\[/           { skip = 0 }
        !skip           { print }
      ' /etc/pacman.conf > "$PACMAN_TMP"
      sudo install -m 0644 -o root -g root "$PACMAN_TMP" /etc/pacman.conf
      rm -f "$PACMAN_TMP"
    fi
  fi

  # Añadir bloques correctos si faltan
  if ! grep -qE '^\[extra\]' /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch
EOF
  fi
  if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
    sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
  fi
else
  # Arch vanilla / Manjaro / EndeavourOS / CachyOS / Garuda / ArcoLinux
  if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
    if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
      sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' /etc/pacman.conf
    else
      sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
  fi
fi

# Limpiar DBs viejas que pudieron quedar registradas con paths rotos
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db 2>/dev/null || true

sudo pacman -Sy --noconfirm

# ---------------------------------------------------------
# 3) Dependencias base
# ---------------------------------------------------------
echo ">> Instalando dependencias base (críticas)"
sudo pacman -S --noconfirm --needed \
  base-devel git wget curl pkgconf gettext unzip zstd patchelf \
  clang lld \
  samba gnutls \
  wine winetricks \
  lib32-glibc lib32-gcc-libs lib32-freetype2 \
  lib32-libx11 lib32-libxext lib32-libxrender lib32-libxrandr lib32-libxxf86vm \
  lib32-libxcomposite lib32-libxcursor lib32-libxfixes lib32-libxi lib32-libxdamage lib32-libxtst \
  libxcomposite libxcursor libxfixes libxi libxdamage libxtst \
  lib32-mesa lib32-libdrm \
  cabextract \
  fontconfig xdg-utils

# Vulkan/OpenGL 32-bit ICD según GPU detectada. Sin esto, wine32 no renderiza
# (ventana sale transparente en KDE Plasma 6 Wayland, GNOME, etc.).
echo ">> Detectando GPU para vulkan ICD 32-bit"
GPU_VENDOR=$(lspci | grep -iE "VGA|3D" | head -1 | grep -ioE "NVIDIA|AMD|Intel" | head -1 || echo "unknown")
case "$GPU_VENDOR" in
  AMD)    sudo pacman -S --noconfirm --needed lib32-vulkan-radeon 2>&1 | tail -2 || true ;;
  Intel)  sudo pacman -S --noconfirm --needed lib32-vulkan-intel  2>&1 | tail -2 || true ;;
  NVIDIA) sudo pacman -S --noconfirm --needed lib32-nvidia-utils  2>&1 | tail -2 || \
          sudo pacman -S --noconfirm --needed lib32-vulkan-nouveau 2>&1 | tail -2 || true ;;
  *)      echo "[WARN] GPU vendor desconocido; instalar manualmente lib32-vulkan-* según tarjeta" ;;
esac

# Deps audio opcionales (Office funciona sin ellas; mirrors CachyOS suelen
# servir 404 en builds específicos de lib32-libpulse/lib32-libasyncns).
sudo pacman -S --noconfirm --needed lib32-alsa-lib 2>&1 | tail -3 || \
  echo "[WARN] lib32-alsa-lib no instalable, Office seguirá sin audio ALSA 32-bit"
sudo pacman -S --noconfirm --needed lib32-libpulse 2>&1 | tail -3 || \
  echo "[WARN] lib32-libpulse no instalable (mirror desync), Office seguirá sin audio PulseAudio 32-bit"

# Deps 32-bit que libgnutls/libnettle bundled de WineCX cargan en runtime.
# Sin éstas: 'err:winediag:gnutls_process_attach failed to load libgnutls,
# no support for encryption' y Office se queda colgado al abrir.
sudo pacman -S --noconfirm --needed \
  lib32-libtasn1 lib32-libidn2 lib32-p11-kit lib32-gmp lib32-libunistring \
  lib32-libnghttp2 lib32-libgpg-error lib32-libgcrypt \
  || echo "[WARN] Algunas deps lib32-gnutls fallaron (revisa multilib)"

# Impresión (opcional, no rompe si falla)
sudo pacman -S --noconfirm --needed cups cups-filters system-config-printer 2>/dev/null || true

# ---------------------------------------------------------
# 4) AUR helper + paquetes AUR
# ---------------------------------------------------------
AUR_HELPER=""
for h in paru yay; do
  if command -v "$h" >/dev/null 2>&1; then AUR_HELPER="$h"; break; fi
done

if [ -z "$AUR_HELPER" ]; then
  echo ">> Instalando yay-bin desde AUR"
  AUR_TMP="$(mktemp -d)"
  pushd "$AUR_TMP" >/dev/null
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$AUR_TMP"
  AUR_HELPER="yay"
fi

echo ">> Paquetes AUR (msitools, ttf-ms-fonts)"
"$AUR_HELPER" -S --needed --noconfirm msitools ttf-ms-fonts 2>/dev/null || \
  echo "[WARN] Fallo al instalar msitools/ttf-ms-fonts desde AUR, continuando"

# ---------------------------------------------------------
# 5.5) Check for native build mode (CachyOS/Manjaro/Fallback)
# ---------------------------------------------------------
if [ "${CACHY_NATIVE_MODE:-0}" = "1" ] || [ -n "${CACHY_USE_NATIVE:-}" ]; then
  echo ">> MODO NATIVO: Instalando Wine desde build nativo..."
  
  # Determine which zip to use
  NATIVE_ZIP=""
  NATIVE_ZIP_SHA=""
  
  if [ "$ID" = "cachyos" ] && [ -f "$WORKDIR/winecx_cachy.zip" ]; then
    NATIVE_ZIP="$WORKDIR/winecx_cachy.zip"
    NATIVE_ZIP_SHA="4dfe3b8b89edc2a65a98f92f19b4ab51b3504052853f1b71f38ff91dd2886219"
    log "Usando winecx_cachy.zip (CachyOS native build)"
  elif [ "$ID" = "manjaro" ] && [ -f "$WORKDIR/winecx_manjaro.zip" ]; then
    NATIVE_ZIP="$WORKDIR/winecx_manjaro.zip"
    NATIVE_ZIP_SHA="456bbe42831fa2e6ac7cc48529ab183e4066383136eae14c80b412d75ea63bc0"
    log "Usando winecx_manjaro.zip (Manjaro native build)"
  elif [ -f "$WORKDIR/winecx_arch.zip" ]; then
    NATIVE_ZIP="$WORKDIR/winecx_arch.zip"
    NATIVE_ZIP_SHA="2459b0920a33a15791100648393e168fe296f248abdb7ae2eb44c932e252c6fe"
    log "Usando winecx_arch.zip (Arch native build)"
  fi
  
  if [ -n "$NATIVE_ZIP" ]; then
    # Verify SHA256
    if echo "$NATIVE_ZIP_SHA  $NATIVE_ZIP" | sha256sum -c --status 2>/dev/null; then
      log "Extrayendo native build..."
      # /opt/winecx puede existir de un install previo con owner root:root.
      sudo rm -rf /opt/winecx
      unzip -q -o "$NATIVE_ZIP" -d /tmp/winecx-native
      
      # Check for build64/build32 directories (make install artifacts)
      if [ -d /tmp/winecx-native/build64 ] && [ -d /tmp/winecx-native/build32 ]; then
        log "Instalando build64..."
        pushd /tmp/winecx-native/build64 >/dev/null
        sudo make install 2>&1 | tail -5 || true
        popd >/dev/null
        
        log "Instalando build32..."
        pushd /tmp/winecx-native/build32 >/dev/null
        sudo make install 2>&1 | tail -5 || true
        popd >/dev/null
      else
        # Just copy the winecx directory
        sudo cp -r /tmp/winecx-native/winecx /opt/ 2>/dev/null || \
        sudo cp -r /tmp/winecx-native/* /opt/winecx/ 2>/dev/null || true
      fi
      
      sudo chown -R root:root /opt/winecx 2>/dev/null || true
      sudo chmod -R 755 /opt/winecx 2>/dev/null || true
      rm -rf /tmp/winecx-native
      
      ok "Native build instalado."
      SKIP_DEB=1
    else
      warn "SHA256 mismatch en native zip, continuando con .deb"
    fi
  fi
fi

if [ "${SKIP_DEB:-0}" != "1" ]; then
  # ---------------------------------------------------------
  # 5) Extraer winecx.deb a /opt/winecx (manual, sin dpkg)
  # ---------------------------------------------------------
  echo ">> Extrayendo winecx.deb"
  [ -f "winecx.deb" ] || { echo "ERROR: winecx.deb falta en $(pwd)" >&2; exit 1; }

  DEB_WORK="$(mktemp -d)"
  pushd "$DEB_WORK" >/dev/null
  cp "$WORKDIR/MSO365/winecx.deb" .
  ar x winecx.deb

  # Detectar nombre de data.tar.* (puede ser xz, zst, gz)
  DATA_TAR=$(ls data.tar.* 2>/dev/null | head -1)
  [ -n "$DATA_TAR" ] || { echo "ERROR: no se encontró data.tar.* dentro de .deb" >&2; exit 1; }

  sudo mkdir -p /opt/winecx
  case "$DATA_TAR" in
    *.zst) sudo tar --zstd -xf "$DATA_TAR" -C /opt/winecx ;;
    *.xz)  sudo tar -xJf "$DATA_TAR" -C /opt/winecx ;;
    *.gz)  sudo tar -xzf "$DATA_TAR" -C /opt/winecx ;;
    *)     sudo tar -xf "$DATA_TAR" -C /opt/winecx ;;
  esac

  # Algunas builds dejan /opt/winecx/opt/winecx -> aplanar
  if [ -d /opt/winecx/opt/winecx ]; then
    sudo cp -a /opt/winecx/opt/winecx/. /opt/winecx/
    sudo rm -rf /opt/winecx/opt
  fi
  popd >/dev/null
  rm -rf "$DEB_WORK"

  sudo chown -R root:root /opt/winecx
  sudo chmod -R 755 /opt/winecx
fi

# ---------------------------------------------------------
# 6) Bundle nettle/gnutls 3.7 (fix ABI break con nettle 4.0 del sistema)
# ---------------------------------------------------------
BUNDLE_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/arch-winecx-libs.tar.zst"
BUNDLE_SHA="6d5f93258a8159fc585d6dc0389e4f42fae6e7814da3ff0e4e750a044aefaf5e"
BUNDLE_TGT="$WORKDIR/arch-winecx-libs.tar.zst"

if [ ! -f "$BUNDLE_TGT" ] || ! echo "$BUNDLE_SHA  $BUNDLE_TGT" | sha256sum -c --status; then
  echo ">> Descargando bundle nettle/gnutls 3.7"
  curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$BUNDLE_TGT" "$BUNDLE_URL"
  echo "$BUNDLE_SHA  $BUNDLE_TGT" | sha256sum -c --status || { echo "ERROR: SHA256 mismatch en bundle" >&2; exit 1; }
fi

echo ">> Extrayendo bundle libs en /opt/winecx"
sudo tar --zstd -xf "$BUNDLE_TGT" -C /opt/winecx/

# Verificación rpath
for lib in /opt/winecx/lib/libhogweed.so.* /opt/winecx/lib32/libhogweed.so.*; do
  [ -f "$lib" ] && [ ! -L "$lib" ] && /opt/winecx/bin/wine --version >/dev/null 2>&1 || true
done

# ----- 6) Verificar que Wine funciona (con LD_LIBRARY_PATH) -----
log "Verificando que WineCX funciona..."
WINE_VER=$(LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  /opt/winecx/bin/wine --version 2>&1 || echo "FAILED")
echo ">> WineCX: $WINE_VER"

if [[ "$WINE_VER" == *"FAILED"* ]] || [[ "$WINE_VER" == *"error"* ]] || [[ "$WINE_VER" == *"command not found"* ]]; then
  warn "WineCX .deb no funciona correctamente en $PRETTY_NAME"
  echo "Diagnóstico: $WINE_VER"
  
  # Check if we should try fallback
  FALLBACK_ZIP=""
  FALLBACK_SHA=""
  FALLBACK_URL=""
  
  if [ "$ID" = "cachyos" ] && [ -f "$WORKDIR/winecx_cachy.zip" ]; then
    FALLBACK_ZIP="winecx_cachy.zip"
    FALLBACK_SHA="4dfe3b8b89edc2a65a98f92f19b4ab51b3504052853f1b71f38ff91dd2886219"
    FALLBACK_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_cachy.zip"
    warn "Intentando fallback: winecx_cachy.zip (CachyOS native build)"
  elif [ "$ID" = "manjaro" ] && [ -f "$WORKDIR/winecx_manjaro.zip" ]; then
    FALLBACK_ZIP="winecx_manjaro.zip"
    FALLBACK_SHA="456bbe42831fa2e6ac7cc48529ab183e4066383136eae14c80b412d75ea63bc0"
    FALLBACK_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_manjaro.zip"
    warn "Intentando fallback: winecx_manjaro.zip (Manjaro native build)"
  elif [ -f "$WORKDIR/winecx_arch.zip" ]; then
    FALLBACK_ZIP="winecx_arch.zip"
    FALLBACK_SHA="2459b0920a33a15791100648393e168fe296f248abdb7ae2eb44c932e252c6fe"
    FALLBACK_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx_arch.zip"
    warn "Intentando fallback: winecx_arch.zip (Arch native build)"
  fi
  
  if [ -n "$FALLBACK_ZIP" ]; then
    # Verify SHA256
    if ! echo "$FALLBACK_SHA  $WORKDIR/$FALLBACK_ZIP" | sha256sum -c --status 2>/dev/null; then
      log "Descargando $FALLBACK_ZIP..."
      curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$WORKDIR/$FALLBACK_ZIP" "$FALLBACK_URL"
      echo "$FALLBACK_SHA  $WORKDIR/$FALLBACK_ZIP" | sha256sum -c --status || \
        { warn "SHA256 mismatch en $FALLBACK_ZIP"; FALLBACK_ZIP=""; }
    fi
    
    if [ -n "$FALLBACK_ZIP" ]; then
      log "Instalando WineCX native build (fallback)..."
      # /opt/winecx existe de la instalación .deb fallida con owner root:root.
      sudo rm -rf /opt/winecx
      unzip -q -o "$WORKDIR/$FALLBACK_ZIP" -d /tmp/winecx-native
      sudo mv /tmp/winecx-native/winecx /opt/ 2>/dev/null || \
        sudo mv /tmp/winecx-native/wine /opt/winecx 2>/dev/null || \
        sudo cp -r /tmp/winecx-native/* /opt/winecx/ 2>/dev/null || true
      sudo chown -R root:root /opt/winecx 2>/dev/null || true
      sudo chmod -R 755 /opt/winecx 2>/dev/null || true
      rm -rf /tmp/winecx-native
      
      # Validate again
      WINE_VER=$(LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
        /opt/winecx/bin/wine --version 2>&1 || echo "FAILED")
      echo ">> WineCX (fallback): $WINE_VER"
      
      if [[ "$WINE_VER" == *"FAILED"* ]] || [[ "$WINE_VER" == *"error"* ]]; then
        die "ERROR: WineCX fallback tampoco funciona. Problema de compatibilidad."
      else
        ok "WineCX fallback instalado y funcionando: $WINE_VER"
      fi
    fi
  else
    die "ERROR: WineCX no arranca y no hay fallback disponible."
  fi
else
  ok "WineCX funcionando: $WINE_VER"
fi

# ---------------------------------------------------------
# 7) Copiar prefix Office 365 al HOME
# ---------------------------------------------------------
echo ">> Copiando prefix Office 365"
if [ -d ".Microsoft_Office_365" ]; then
  cp -r .Microsoft_Office_365 "$HOME"
else
  echo "ERROR: prefix .Microsoft_Office_365 no encontrado dentro de MSO365/" >&2
  exit 1
fi

# ---------------------------------------------------------
# 8) Íconos
# ---------------------------------------------------------
sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
sudo cp Office2016Icons/*365.svg /usr/share/icons/hicolor/256x256/apps/
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true

# ---------------------------------------------------------
# 9) Lanzadores (con LD_LIBRARY_PATH para libs bundled)
# ---------------------------------------------------------
sudo mkdir -p /opt/winecx/launchers
sudo chmod 755 /opt/winecx/launchers

create_launcher() {
  local name="$1" exe="$2"
  sudo tee "/opt/winecx/launchers/${name}.sh" > /dev/null <<EOF
#!/bin/bash
set -e
export LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine:\$LD_LIBRARY_PATH"
export PATH="/opt/winecx/bin:\$PATH"
export WINEPREFIX="\$HOME/.Microsoft_Office_365"
export LANG=C.UTF-8
export WINEDEBUG=-all

app="C:\\\\Program Files\\\\Microsoft Office\\\\root\\\\Office16\\\\${exe}"
/opt/winecx/bin/wineserver -p >/dev/null 2>&1 || true

if [ \$# -eq 0 ]; then
    exec /opt/winecx/bin/wine "\$app"
else
    for file in "\$@"; do
        fullpath=\$(realpath "\$file")
        winpath="Z:\${fullpath//\//\\\\}"
        /opt/winecx/bin/wine "\$app" "\$winpath"
    done
fi
EOF
  sudo chmod +x "/opt/winecx/launchers/${name}.sh"
}

create_desktop() {
  local name="$1" display="$2" comment="$3" icon="$4" categories="$5" mimetypes="$6" wmclass="$7"
  sudo tee "/usr/share/applications/${name}.desktop" > /dev/null <<EOF
[Desktop Entry]
Name=${display}
Comment=${comment}
Exec=/opt/winecx/launchers/${name}.sh %F
Type=Application
StartupNotify=true
StartupWMClass=${wmclass}
Terminal=false
Icon=${icon}
Categories=${categories}
MimeType=${mimetypes}
EOF
}

create_launcher "word365" "WINWORD.EXE"
create_desktop  "word365" "Microsoft Word 365" "Procesador de textos de Microsoft Office 365" "Word365" \
  "Office;WordProcessor;" \
  "application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.ms-word.document.macroEnabled.12;application/rtf;text/plain;" \
  "winword.exe"

create_launcher "excel365" "EXCEL.EXE"
create_desktop  "excel365" "Microsoft Excel 365" "Hoja de cálculo de Microsoft Office 365" "Excel365" \
  "Office;Spreadsheet;" \
  "application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.ms-excel.sheet.macroEnabled.12;text/csv;" \
  "excel.exe"

create_launcher "powerpoint365" "POWERPNT.EXE"
create_desktop  "powerpoint365" "Microsoft PowerPoint 365" "Presentaciones de Microsoft Office 365" "Powerpoint365" \
  "Office;Presentation;" \
  "application/vnd.ms-powerpoint;application/vnd.openxmlformats-officedocument.presentationml.presentation;application/vnd.ms-powerpoint.presentation.macroEnabled.12;" \
  "powerpnt.exe"

create_launcher "outlook365" "OUTLOOK.EXE"
create_desktop  "outlook365" "Microsoft Outlook 365" "Cliente de correo de Microsoft Office 365" "Outlook365" \
  "Office;Email;" \
  "application/vnd.ms-outlook;application/mbox;message/rfc822;" \
  "outlook.exe"

create_launcher "access365" "MSACCESS.EXE"
create_desktop  "access365" "Microsoft Access 365" "Base de datos de Microsoft Office 365" "Access365" \
  "Office;Database;" \
  "application/vnd.ms-access;application/x-msaccess;" \
  "msaccess.exe"

create_launcher "publisher365" "MSPUB.EXE"
create_desktop  "publisher365" "Microsoft Publisher 365" "Publicaciones de Microsoft Office 365" "Publisher365" \
  "Office;Publishing;" \
  "application/x-mspublisher;" \
  "mspub.exe"

# Kill switch para todos los procesos Office/Wine
sudo tee /opt/winecx/launchers/kill_office.sh > /dev/null <<'EOF'
#!/bin/bash
echo "Cerrando procesos Office/Wine..."
pkill -KILL -f '/opt/winecx' 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k 2>/dev/null || true
echo "Listo."
EOF
sudo chmod +x /opt/winecx/launchers/kill_office.sh

sudo tee /usr/share/applications/kill_office.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Kill Office 365
Comment=Forzar cierre de procesos Office y Wine
Exec=/opt/winecx/launchers/kill_office.sh
Type=Application
Terminal=true
Icon=process-stop
Categories=Office;System;
EOF

sudo update-desktop-database /usr/share/applications || true

# Asociaciones MIME
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default word365.desktop \
    application/msword \
    application/vnd.openxmlformats-officedocument.wordprocessingml.document \
    application/vnd.ms-word.document.macroEnabled.12 \
    application/rtf 2>/dev/null || true
  xdg-mime default excel365.desktop \
    application/vnd.ms-excel \
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
    application/vnd.ms-excel.sheet.macroEnabled.12 \
    text/csv 2>/dev/null || true
  xdg-mime default powerpoint365.desktop \
    application/vnd.ms-powerpoint \
    application/vnd.openxmlformats-officedocument.presentationml.presentation \
    application/vnd.ms-powerpoint.presentation.macroEnabled.12 2>/dev/null || true
  xdg-mime default outlook365.desktop \
    application/vnd.ms-outlook message/rfc822 2>/dev/null || true
  xdg-mime default access365.desktop \
    application/vnd.ms-access application/x-msaccess 2>/dev/null || true
  xdg-mime default publisher365.desktop \
    application/x-mspublisher 2>/dev/null || true
fi

# ---------------------------------------------------------
# 10) Permisos prefix + dosdevices
# ---------------------------------------------------------
sudo chown -R "$USER:$USER" "$HOME/.Microsoft_Office_365"
sudo chmod -R u+rwX "$HOME/.Microsoft_Office_365"

rm -rf "$HOME/.Microsoft_Office_365/dosdevices"
mkdir -p "$HOME/.Microsoft_Office_365/dosdevices"
ln -s ../drive_c "$HOME/.Microsoft_Office_365/dosdevices/c:"
ln -s /          "$HOME/.Microsoft_Office_365/dosdevices/z:"
ln -s /dev/null  "$HOME/.Microsoft_Office_365/dosdevices/c::"
ln -s /dev/null  "$HOME/.Microsoft_Office_365/dosdevices/z::"
ln -s /media     "$HOME/.Microsoft_Office_365/dosdevices/d:"
ln -s "$HOME"    "$HOME/.Microsoft_Office_365/dosdevices/e:"

mkdir -p "$HOME/.Microsoft_Office_365/drive_c/users/crossover/AppData/Local"
mkdir -p "$HOME/.Microsoft_Office_365/drive_c/users/crossover/AppData/Roaming"

# ---------------------------------------------------------
# 11) wineboot -u (con LD_LIBRARY_PATH)
# ---------------------------------------------------------
echo ">> Inicializando prefix"
LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  WINEPREFIX="$HOME/.Microsoft_Office_365" \
  /opt/winecx/bin/wine wineboot -u || true

LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  WINEPREFIX="$HOME/.Microsoft_Office_365" \
  /opt/winecx/bin/wine wineboot -e || true
LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  WINEPREFIX="$HOME/.Microsoft_Office_365" \
  /opt/winecx/bin/wineserver -k || true
LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  WINEPREFIX="$HOME/.Microsoft_Office_365" \
  /opt/winecx/bin/wineserver -w || true

# ---------------------------------------------------------
# 12) Fuentes Office (en prefix Y en /usr/share/fonts/Windows)
# ---------------------------------------------------------
mkdir -p "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts"
if [ -d "$WORKDIR/MSO365/Fuentes Office365" ]; then
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttf "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.TTF "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttc "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true

  sudo mkdir -p /usr/share/fonts/Windows
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttf /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.TTF /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttc /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo fc-cache -f /usr/share/fonts/Windows >/dev/null 2>&1 || true
fi

# Registrar fuentes en registry wine
LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
WINEPREFIX="$HOME/.Microsoft_Office_365" bash -c '
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
/opt/winecx/bin/wine regedit "$REGFILE" || true
'

# ---------------------------------------------------------
# 13) Desactivar Office updates
# ---------------------------------------------------------
LD_LIBRARY_PATH="/opt/winecx/lib:/opt/winecx/lib32:/opt/winecx/lib/wine" \
  WINEPREFIX="$HOME/.Microsoft_Office_365" \
  /opt/winecx/bin/wine reg add \
  "HKLM\\Software\\Microsoft\\Office\\ClickToRun\\Configuration" \
  /v UpdateChannel /t REG_SZ /d "Deferred" /f 2>/dev/null || true

# Limpiar MRU
PREFIX="$HOME/.Microsoft_Office_365"
if [ -f "$PREFIX/user.reg" ]; then
  sed -i '/File MRU/,+20d'  "$PREFIX/user.reg"
  sed -i '/Place MRU/,+20d' "$PREFIX/user.reg"
  sed -i '/User MRU/,+20d'  "$PREFIX/user.reg"
fi

# ---------------------------------------------------------
# 14) CUPS (opcional, según init)
# ---------------------------------------------------------
if command -v cupsd >/dev/null 2>&1; then
  case "$INIT" in
    systemd) sudo systemctl enable --now cups 2>/dev/null || true ;;
    runit)   [ -d /etc/runit/sv/cupsd ] && sudo ln -sf /etc/runit/sv/cupsd /run/runit/service/ 2>/dev/null && sudo sv start cupsd 2>/dev/null || true ;;
    openrc)  sudo rc-update add cupsd default 2>/dev/null && sudo rc-service cupsd start 2>/dev/null || true ;;
    s6)      [ -d /etc/s6/sv/cupsd ] && sudo s6-rc-bundle-update add default cupsd 2>/dev/null || true ;;
    dinit)   sudo dinitctl enable cupsd 2>/dev/null || true ;;
  esac
fi

echo "==============================================="
echo "  Office 365 instalado correctamente en $PRETTY_NAME"
echo "==============================================="
echo
echo "Lanza Word/Excel/PowerPoint/Outlook/Access/Publisher desde tu menú."
echo "Cierra forzado: ejecutar 'Kill Office 365' desde menú."
