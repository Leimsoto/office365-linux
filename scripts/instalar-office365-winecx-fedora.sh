#!/bin/bash
# Instalador Office 365 + WineCX para Fedora y derivadas (RHEL, Rocky,
# AlmaLinux, CentOS Stream, Nobara, Ultramarine, Bazzite).
# Usa WineCX Fedora-compiled (Wine 10.0 vanilla, sin bundle nettle/gnutls).
# Standalone OK desde $HOME/Descargas o invocado por install.sh.

set -euo pipefail

echo "==============================================="
echo "  Office 365 - WineCX (Fedora / RHEL / Rocky)"
echo "==============================================="

WORKDIR="${OFFICE365_WORKDIR:-$HOME/Descargas}"
cd "$WORKDIR"

. /etc/os-release 2>/dev/null || { echo "ERROR: /etc/os-release no encontrado" >&2; exit 1; }
INIT_SYSTEM="$(cat /proc/1/comm 2>/dev/null || echo unknown)"
echo ">> Distro: $PRETTY_NAME (init: $INIT_SYSTEM)"

# ---------------------------------------------------------
# 1) MSO365.zip
# ---------------------------------------------------------
if [ ! -d "MSO365" ]; then
  [ -f "MSO365.zip" ] || { echo "ERROR: falta MSO365.zip en $WORKDIR" >&2; exit 1; }
  command -v unzip >/dev/null 2>&1 || sudo dnf install -y unzip
  unzip -o MSO365.zip
fi
cd "$WORKDIR/MSO365"

# ---------------------------------------------------------
# 2) RPM Fusion + multilib i686 hint
# ---------------------------------------------------------
echo ">> Habilitando RPM Fusion (free + nonfree) si falta"
sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
  2>/dev/null || true

# ---------------------------------------------------------
# 3) Dependencias runtime (no -devel, solo libs para correr wine + Office)
# ---------------------------------------------------------
echo ">> Instalando dependencias runtime"
sudo dnf install -y \
  glibc.i686 libstdc++.i686 libgcc.i686 \
  libX11.i686 libXext.i686 libXi.i686 libXcursor.i686 \
  libXrandr.i686 libXrender.i686 libXinerama.i686 libXcomposite.i686 \
  libXfixes.i686 libXdamage.i686 libXxf86vm.i686 libXtst.i686 \
  libxkbcommon.i686 libxkbcommon-x11.i686 \
  freetype.i686 fontconfig.i686 \
  libpng.i686 libjpeg-turbo.i686 \
  alsa-lib.i686 pulseaudio-libs.i686 \
  mesa-libGL.i686 mesa-libEGL.i686 libglvnd-glx.i686 libglvnd-egl.i686 \
  ncurses-libs.i686 \
  libxml2.i686 libxslt.i686 \
  libusb1.i686 \
  harfbuzz.i686 \
  gnutls.i686 libgcrypt.i686 libgpg-error.i686 \
  nettle.i686 \
  libtasn1.i686 libidn2.i686 libunistring.i686 p11-kit.i686 \
  krb5-libs.i686 openldap.i686 \
  cups-libs.i686 \
  zlib-ng-compat.i686 || \
sudo dnf install -y zlib.i686 || true

# 64-bit utilidades
sudo dnf install -y \
  cabextract msitools \
  samba samba-winbind \
  cups system-config-printer cups-pdf \
  curl wget tar unzip zstd \
  fontconfig xdg-utils desktop-file-utils gtk-update-icon-cache \
  2>&1 | tail -5 || true

# ttf-mscorefonts: paquete tercero por RPM Fusion / build manual
sudo dnf install -y \
  https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm \
  2>/dev/null || true

# winetricks: a veces empaquetado, sino curl
if ! command -v winetricks >/dev/null 2>&1; then
  sudo curl -fsSL -o /usr/local/bin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
  sudo chmod +x /usr/local/bin/winetricks
fi

# ---------------------------------------------------------
# 4) Instalar WineCX Fedora-compiled
# ---------------------------------------------------------
WINECX_ZIP="$WORKDIR/winecx-fedora.zip"
WINECX_SHA="4835f40619af3d44b49e313d5eabfdb3442c15025d3d79d62760c9532bc58656"

if [ ! -f "$WINECX_ZIP" ] || ! echo "$WINECX_SHA  $WINECX_ZIP" | sha256sum -c --status; then
  echo ">> Descargando WineCX Fedora (~432 MB)"
  curl -fL --retry 5 --retry-delay 3 --progress-bar \
    -o "$WINECX_ZIP" \
    "https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0/winecx-fedora.zip"
  echo "$WINECX_SHA  $WINECX_ZIP" | sha256sum -c --status || \
    { echo "ERROR: SHA256 mismatch winecx-fedora.zip" >&2; exit 1; }
fi

echo ">> Extrayendo WineCX a /opt"
sudo rm -rf /opt/winecx
WORK_EXTRACT=$(mktemp -d)
unzip -q -o "$WINECX_ZIP" -d "$WORK_EXTRACT"
sudo mv "$WORK_EXTRACT/winecx" /opt/
rm -rf "$WORK_EXTRACT"

sudo chown -R root:root /opt/winecx
sudo chmod -R 755 /opt/winecx

# Sanity check
WINE_VER=$(/opt/winecx/bin/wine --version 2>&1 || echo "FAILED")
echo ">> WineCX: $WINE_VER"
[[ "$WINE_VER" == "FAILED" ]] && { echo "ERROR: WineCX no arranca" >&2; exit 1; }

# ---------------------------------------------------------
# 5) Copiar prefix Office 365
# ---------------------------------------------------------
echo ">> Copiando prefix Office 365"
[ -d ".Microsoft_Office_365" ] || { echo "ERROR: prefix no encontrado en MSO365/"; exit 1; }
cp -r .Microsoft_Office_365 "$HOME"

# ---------------------------------------------------------
# 6) Íconos
# ---------------------------------------------------------
sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
sudo cp Office2016Icons/*365.svg /usr/share/icons/hicolor/256x256/apps/
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true

# ---------------------------------------------------------
# 7) Launchers + .desktop
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

# Kill switch
sudo tee /opt/winecx/launchers/kill_office.sh > /dev/null <<'EOF'
#!/bin/bash
pkill -KILL -f '/opt/winecx' 2>/dev/null || true
pkill -KILL -f 'WINWORD\.EXE|EXCEL\.EXE|POWERPNT\.EXE|OUTLOOK\.EXE|MSACCESS\.EXE|MSPUB\.EXE|OfficeClickToRun\.exe' 2>/dev/null || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k 2>/dev/null || true
notify-send "Office 365" "Procesos cerrados" 2>/dev/null || true
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
  xdg-mime default outlook365.desktop application/vnd.ms-outlook message/rfc822 2>/dev/null || true
  xdg-mime default access365.desktop application/vnd.ms-access application/x-msaccess 2>/dev/null || true
  xdg-mime default publisher365.desktop application/x-mspublisher 2>/dev/null || true
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
# 9) wineboot -u (sin LD_LIBRARY_PATH - wine vanilla usa libs sistema)
# ---------------------------------------------------------
echo ">> Inicializando prefix"
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine wineboot -u || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine wineboot -e || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -w || true

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
# 11) Desactivar Office updates + MRU
# ---------------------------------------------------------
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine reg add \
  "HKLM\\Software\\Microsoft\\Office\\ClickToRun\\Configuration" \
  /v UpdateChannel /t REG_SZ /d "Deferred" /f 2>/dev/null || true

PREFIX="$HOME/.Microsoft_Office_365"
if [ -f "$PREFIX/user.reg" ]; then
  sed -i '/File MRU/,+20d'  "$PREFIX/user.reg"
  sed -i '/Place MRU/,+20d' "$PREFIX/user.reg"
  sed -i '/User MRU/,+20d'  "$PREFIX/user.reg"
fi

# ---------------------------------------------------------
# 12) CUPS (systemd) - Fedora siempre systemd
# ---------------------------------------------------------
if command -v cupsd >/dev/null 2>&1; then
  sudo systemctl enable --now cups 2>/dev/null || true
fi

echo "==============================================="
echo "  Office 365 instalado correctamente en $PRETTY_NAME"
echo "==============================================="
echo
echo "Lanza Word/Excel/PowerPoint/Outlook/Access/Publisher desde tu menú."
echo "Cierra forzado: 'Kill Office 365' desde menú."
