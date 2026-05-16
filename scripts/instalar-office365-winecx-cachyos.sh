#!/bin/bash
# Instalador Office 365 + WineCX para CachyOS (build especial pre-compilado).
# CachyOS necesita WineCX compilado contra su propio stack (nettle, glibc,
# mesa). Reusar el .deb Debian o el bundle nettle 3.7 falla con
# OfficeClickToRun 0x6d3 o renderizado roto. Este path usa un winecx
# pre-construido EN CachyOS y empaquetado con `make install` desde build64/
# y build32/.
#
# Standalone OK desde $HOME/Descargas o invocado por install.sh.

set -euo pipefail

echo "==============================================="
echo "  Office 365 - WineCX (CachyOS native build)"
echo "==============================================="

WORKDIR="${OFFICE365_WORKDIR:-$HOME/Descargas}"
cd "$WORKDIR"

. /etc/os-release 2>/dev/null || { echo "ERROR: /etc/os-release no encontrado" >&2; exit 1; }
echo ">> Distro: $PRETTY_NAME"
[ "$ID" = "cachyos" ] || \
  echo "[WARN] Distro no es CachyOS, este build puede no ser ABI-compatible. Use --family=arch para path estándar."

# ---------------------------------------------------------
# 1) MSO365.zip
# ---------------------------------------------------------
if [ ! -d "MSO365" ]; then
  [ -f "MSO365.zip" ] || { echo "ERROR: falta MSO365.zip en $WORKDIR" >&2; exit 1; }
  command -v unzip >/dev/null 2>&1 || sudo pacman -S --noconfirm --needed unzip
  unzip -o MSO365.zip
fi
cd "$WORKDIR/MSO365"

# ---------------------------------------------------------
# 2) Multilib + Architecture en pacman.conf
# ---------------------------------------------------------
echo ">> Habilitando multilib"
if ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a Architecture = auto' /etc/pacman.conf
fi
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
sudo pacman -Sy --noconfirm

# ---------------------------------------------------------
# 3) Dependencias compilación + runtime
# ---------------------------------------------------------
echo ">> Instalando dependencias"
sudo pacman -S --needed --noconfirm \
  base-devel gcc gcc-multilib clang lld flex bison \
  git wget curl pkgconf gettext rsync \
  lib32-glibc lib32-gcc-libs \
  lib32-alsa-lib lib32-alsa-plugins \
  lib32-libx11 lib32-libxext lib32-libxrender lib32-libxrandr \
  lib32-libxcursor lib32-libxfixes lib32-libxi lib32-libxcomposite \
  lib32-libxdamage lib32-libxcb lib32-libxxf86vm lib32-libxtst \
  libxcomposite libxcursor libxfixes libxi libxdamage libxtst libxrandr libxrender \
  lib32-freetype2 lib32-libpng lib32-fontconfig \
  lib32-libgcrypt lib32-libgpg-error lib32-gnutls \
  lib32-libsm lib32-libice lib32-glu lib32-mesa \
  lib32-giflib lib32-libjpeg-turbo lib32-libtiff lib32-lcms2 \
  lib32-libxslt lib32-libxml2 \
  libxkbcommon lib32-libxkbcommon libxkbcommon-x11 \
  pcsclite lib32-pcsclite krb5 lib32-krb5 \
  sdl2 lib32-sdl2 gstreamer lib32-gstreamer gst-plugins-base lib32-gst-plugins-base \
  dbus lib32-dbus gnutls lib32-gnutls libpcap lib32-libpcap \
  opencl-icd-loader ocl-icd \
  mingw-w64-binutils mingw-w64-gcc \
  cups cups-pdf system-config-printer \
  msitools \
  sane libcups lib32-libcups \
  v4l-utils lib32-v4l-utils gphoto2 gsm openal lib32-openal \
  vulkan-icd-loader lib32-vulkan-icd-loader \
  libusb lib32-libusb udev lib32-systemd \
  samba lib32-libxft cabextract \
  winetricks fontconfig xdg-utils 2>&1 | tail -3 || \
  echo "[WARN] Algunas dependencias fallaron, continuando"

# GPU vulkan ICD 32-bit
echo ">> Detectando GPU"
GPU_VENDOR=$(lspci | grep -iE "VGA|3D" | head -1 | grep -ioE "NVIDIA|AMD|Intel" | head -1 || echo "")
case "$GPU_VENDOR" in
  AMD)    sudo pacman -S --noconfirm --needed lib32-vulkan-radeon 2>&1 | tail -2 || true ;;
  Intel)  sudo pacman -S --noconfirm --needed lib32-vulkan-intel  2>&1 | tail -2 || true ;;
  NVIDIA) sudo pacman -S --noconfirm --needed lib32-nvidia-utils  2>&1 | tail -2 || true ;;
esac

# ---------------------------------------------------------
# 4) Descargar y extraer WineCX CachyOS build (1 GB)
# ---------------------------------------------------------
WINECX_ZIP="$WORKDIR/winecx-cachyos.zip"
WINECX_SHA="4dfe3b8b89edc2a65a98f92f19b4ab51b3504052853f1b71f38ff91dd2886219"

if [ ! -f "$WINECX_ZIP" ] || ! echo "$WINECX_SHA  $WINECX_ZIP" | sha256sum -c --status; then
  echo ">> Descargando WineCX CachyOS (~1 GB)"
  curl -fL --retry 5 --retry-delay 3 --progress-bar \
    -o "$WINECX_ZIP" \
    "https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx-cachyos.zip"
  echo "$WINECX_SHA  $WINECX_ZIP" | sha256sum -c --status || \
    { echo "ERROR: SHA256 mismatch winecx-cachyos.zip" >&2; exit 1; }
fi

# Limpiar instalación previa
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k 2>/dev/null || true
sudo rm -rf /opt/winecx
sudo mkdir -p /opt/winecx

echo ">> Extrayendo build tree"
EXTRACT_DIR="$WORKDIR/wine-cachyos-build"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unzip -q -o "$WINECX_ZIP" -d "$EXTRACT_DIR"

# Estructura esperada: $EXTRACT_DIR/wine/build64 y $EXTRACT_DIR/wine/build32
BUILD64="$EXTRACT_DIR/wine/build64"
BUILD32="$EXTRACT_DIR/wine/build32"
[ -d "$BUILD64" ] || { echo "ERROR: build64 no encontrado en zip" >&2; exit 1; }
[ -d "$BUILD32" ] || { echo "ERROR: build32 no encontrado en zip" >&2; exit 1; }

echo ">> make install build64 (~1 min)"
cd "$BUILD64"
sudo make install 2>&1 | tail -3

echo ">> make install build32 (~1 min)"
cd "$BUILD32"
sudo make install 2>&1 | tail -3

sudo chown -R root:root /opt/winecx
sudo chmod -R 755 /opt/winecx

# Cleanup build tree (3.5 GB)
rm -rf "$EXTRACT_DIR"

WINE_VER=$(/opt/winecx/bin/wine --version 2>&1 || echo "FAILED")
echo ">> WineCX: $WINE_VER"
[[ "$WINE_VER" == "FAILED" ]] && { echo "ERROR: WineCX no arranca tras make install" >&2; exit 1; }

# ---------------------------------------------------------
# 5) Copiar prefix Office 365
# ---------------------------------------------------------
echo ">> Copiando prefix Office 365"
[ -d "$WORKDIR/MSO365/.Microsoft_Office_365" ] || \
  { echo "ERROR: prefix no encontrado en MSO365/"; exit 1; }
rm -rf "$HOME/.Microsoft_Office_365"
rsync -a --info=progress2 "$WORKDIR/MSO365/.Microsoft_Office_365" "$HOME/"

# ---------------------------------------------------------
# 6) Íconos
# ---------------------------------------------------------
sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
sudo cp "$WORKDIR/MSO365/Office2016Icons/"*365.svg /usr/share/icons/hicolor/256x256/apps/
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true

# ---------------------------------------------------------
# 7) Launchers + .desktop (sin LD_LIBRARY_PATH; build CachyOS no necesita bundle)
# ---------------------------------------------------------
sudo mkdir -p /opt/winecx/launchers
sudo chmod 755 /opt/winecx/launchers

create_launcher() {
  local name="$1" exe="$2"
  sudo tee "/opt/winecx/launchers/${name}.sh" > /dev/null <<EOF
#!/bin/bash
set -e
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
create_desktop  "word365" "Microsoft Word 365" "Procesador de textos" "Word365" \
  "Office;WordProcessor;" \
  "application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.ms-word.document.macroEnabled.12;application/rtf;text/plain;" \
  "winword.exe"

create_launcher "excel365" "EXCEL.EXE"
create_desktop  "excel365" "Microsoft Excel 365" "Hoja de cálculo" "Excel365" \
  "Office;Spreadsheet;" \
  "application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.ms-excel.sheet.macroEnabled.12;text/csv;" \
  "excel.exe"

create_launcher "powerpoint365" "POWERPNT.EXE"
create_desktop  "powerpoint365" "Microsoft PowerPoint 365" "Presentaciones" "Powerpoint365" \
  "Office;Presentation;" \
  "application/vnd.ms-powerpoint;application/vnd.openxmlformats-officedocument.presentationml.presentation;application/vnd.ms-powerpoint.presentation.macroEnabled.12;" \
  "powerpnt.exe"

create_launcher "outlook365" "OUTLOOK.EXE"
create_desktop  "outlook365" "Microsoft Outlook 365" "Correo electrónico" "Outlook365" \
  "Office;Email;" \
  "application/vnd.ms-outlook;application/mbox;message/rfc822;" \
  "outlook.exe"

create_launcher "access365" "MSACCESS.EXE"
create_desktop  "access365" "Microsoft Access 365" "Base de datos" "Access365" \
  "Office;Database;" \
  "application/vnd.ms-access;application/x-msaccess;" \
  "msaccess.exe"

create_launcher "publisher365" "MSPUB.EXE"
create_desktop  "publisher365" "Microsoft Publisher 365" "Publicaciones" "Publisher365" \
  "Office;Publishing;" \
  "application/x-mspublisher;" \
  "mspub.exe"

# Kill switch
sudo tee /opt/winecx/launchers/kill_office.sh > /dev/null <<'EOF'
#!/bin/bash
pkill -KILL -f '/opt/winecx' 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k 2>/dev/null || true
EOF
sudo chmod +x /opt/winecx/launchers/kill_office.sh
sudo tee /usr/share/applications/kill_office.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Kill Office 365
Exec=/opt/winecx/launchers/kill_office.sh
Type=Application
Terminal=true
Icon=process-stop
Categories=Office;System;
EOF

sudo update-desktop-database /usr/share/applications || true

# xdg-mime
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default word365.desktop \
    application/msword \
    application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
  xdg-mime default excel365.desktop \
    application/vnd.ms-excel \
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv 2>/dev/null || true
  xdg-mime default powerpoint365.desktop \
    application/vnd.ms-powerpoint \
    application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true
fi

# ---------------------------------------------------------
# 8) Permisos prefix + dosdevices
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
# 9) wineboot
# ---------------------------------------------------------
echo ">> Inicializando prefix"
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine wineboot -u || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k || true

# ---------------------------------------------------------
# 10) Fuentes
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

WINEPREFIX="$HOME/.Microsoft_Office_365" bash -c '
FONTDIR="$WINEPREFIX/drive_c/windows/Fonts"
REGFILE="$WINEPREFIX/allfonts.reg"
{
  echo "REGEDIT4"; echo ""
  echo "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]"
  for f in "$FONTDIR"/*.ttf "$FONTDIR"/*.TTF "$FONTDIR"/*.otf "$FONTDIR"/*.OTF "$FONTDIR"/*.ttc "$FONTDIR"/*.TTC; do
    [ -e "$f" ] || continue
    base=$(basename "$f"); name="${base%.*}"
    label=$(echo "$name" | sed "s/_/ /g" | sed "s/Regular//g")
    echo "\"$label (TrueType)\"=\"${base}\""
  done
} > "$REGFILE"
/opt/winecx/bin/wine regedit "$REGFILE" || true
'

# Limpiar MRU
PREFIX="$HOME/.Microsoft_Office_365"
if [ -f "$PREFIX/user.reg" ]; then
  sed -i '/File MRU/,+20d'  "$PREFIX/user.reg"
  sed -i '/Place MRU/,+20d' "$PREFIX/user.reg"
  sed -i '/User MRU/,+20d'  "$PREFIX/user.reg"
fi

echo "==============================================="
echo "  Office 365 instalado correctamente en CachyOS"
echo "==============================================="
