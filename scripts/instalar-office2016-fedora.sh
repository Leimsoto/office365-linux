#!/bin/bash
# Instalador Office 2016 (32-bit) para Fedora — path alternativo al Office 365
# cuando 365 no funciona (Click-to-Run incompatible con vanilla wine 10).
#
# A diferencia del path 365, Office 2016 NO usa Click-to-Run, así que corre
# con Wine 10 vanilla compilado en Fedora. Requiere instalación interactiva
# desde ISO + activación manual posterior.
#
# Assets auto-descargados:
#   - OfPro.ISO                       (Office 2016 instalador, archive.org)
#   - winecx-fedora.zip               (Wine 10 vanilla Fedora 42 build)
#   - Requerimientos-Office-2016.zip  (gecko/mono MSI, icons, DLLs OSPP)
#   - FuentesOffice365.zip            (fuentes Office)
#
# Activación: tras instalar, el usuario aplica su propio activador (no
# redistribuido). El script deja el path /opt/wine/launchers listo.

set -euo pipefail

echo "==============================================="
echo "  Office 2016 - Wine (Fedora / RHEL / Rocky)"
echo "  Path alternativo cuando Office 365 falla"
echo "==============================================="

WORKDIR="${OFFICE365_WORKDIR:-$HOME/Descargas}"
cd "$WORKDIR"
PREFIX="$HOME/.office2016"

. /etc/os-release 2>/dev/null || { echo "ERROR: /etc/os-release no encontrado" >&2; exit 1; }
echo ">> Distro: $PRETTY_NAME"

ISO_FILE="$WORKDIR/OfPro.ISO"
ISO_URL="https://archive.org/download/of-pro/OfPro.ISO"
ISO_SHA="020048505e3e7ebc9b4f556b1a9925677922bfc4c6ed94cba0e96dd89f82a75a"

# Auto-descarga ISO si falta / si SHA no coincide
if [ ! -f "$ISO_FILE" ] || ! echo "$ISO_SHA  $ISO_FILE" | sha256sum -c --status; then
  echo ">> Descargando ISO Office 2016 (~820 MB desde archive.org)"
  curl -fL --retry 5 --retry-delay 3 --progress-bar -o "$ISO_FILE" "$ISO_URL"
  echo "$ISO_SHA  $ISO_FILE" | sha256sum -c --status || \
    { echo "ERROR: SHA256 mismatch en $ISO_FILE" >&2; exit 1; }
fi

# ---------------------------------------------------------
# 1) RPM Fusion + dependencias runtime + compilación
# ---------------------------------------------------------
echo ">> RPM Fusion"
sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
  2>/dev/null || true

echo ">> Dependencias runtime + compilación"
sudo dnf install -y \
  gcc gcc-c++ clang llvm lld flex bison \
  glibc-devel glibc-devel.i686 \
  libX11-devel libX11-devel.i686 libXext-devel libXext-devel.i686 \
  libXinerama-devel libXinerama-devel.i686 libXrender-devel libXrender-devel.i686 \
  libXi-devel libXi-devel.i686 libXcursor-devel libXcursor-devel.i686 \
  libXrandr-devel libXrandr-devel.i686 libXcomposite-devel libXcomposite-devel.i686 \
  libXfixes-devel libXfixes-devel.i686 libXdamage-devel libXdamage-devel.i686 \
  libxkbcommon-devel libxkbcommon-x11-devel \
  freetype-devel freetype-devel.i686 fontconfig-devel fontconfig-devel.i686 \
  libpng-devel libpng-devel.i686 libjpeg-turbo-devel libjpeg-turbo-devel.i686 \
  libtiff-devel libtiff-devel.i686 libxml2-devel libxml2-devel.i686 \
  libxslt-devel libxslt-devel.i686 libunwind-devel libunwind-devel.i686 \
  wayland-devel wayland-devel.i686 \
  alsa-lib-devel alsa-lib-devel.i686 pulseaudio-libs-devel pulseaudio-libs-devel.i686 \
  cups-devel cups-devel.i686 sane-backends-devel sane-backends-devel.i686 \
  libv4l-devel libv4l-devel.i686 libgphoto2-devel libgphoto2-devel.i686 \
  gsm-devel gsm-devel.i686 openal-soft-devel openal-soft-devel.i686 \
  vulkan-loader-devel vulkan-loader-devel.i686 \
  mesa-libGL-devel mesa-libGL-devel.i686 mesa-libEGL-devel mesa-libEGL-devel.i686 \
  systemd-devel systemd-devel.i686 \
  libusb1-devel libusb1-devel.i686 \
  pcsc-lite-devel pcsc-lite-devel.i686 \
  krb5-devel krb5-devel.i686 \
  gnutls-devel gnutls-devel.i686 \
  openldap-devel openldap-devel.i686 \
  libpcap-devel libpcap-devel.i686 \
  ocl-icd-devel ocl-icd-devel.i686 \
  git wget curl pkgconf-pkg-config gettext \
  SDL2-devel gstreamer1-devel gstreamer1-plugins-base-devel dbus-devel \
  bzip2-devel.i686 harfbuzz-devel.i686 \
  glib2-devel.i686 graphite2-devel.i686 \
  mesa-libGL.i686 mesa-libEGL.i686 libglvnd-glx.i686 ncurses-libs.i686 \
  libXcomposite.i686 libXcursor.i686 libXrandr.i686 libXinerama.i686 libXdamage.i686 \
  pulseaudio-libs.i686 sane-backends-libs.i686 libusb1.i686 \
  msitools cabextract wine winetricks samba samba-winbind gnutls \
  cups cups-pdf system-config-printer \
  unzip zstd 7zip xdg-utils 2>&1 | tail -5 || \
  echo "[WARN] Algunas deps fallaron, continuando"

# mingw para wine32 build extra (opcional)
sudo dnf install -y mingw64-gcc mingw64-gcc-c++ mingw64-binutils \
  mingw32-gcc mingw32-gcc-c++ mingw32-binutils 2>/dev/null || true
[ -e /usr/bin/dlltool ] || sudo ln -sf /usr/bin/x86_64-w64-mingw32-dlltool /usr/bin/dlltool 2>/dev/null || true

# ---------------------------------------------------------
# 2) Bajar assets repo: winecx-fedora.zip + Requerimientos + Fuentes
# ---------------------------------------------------------
BASE_URL="https://github.com/Leimsoto/office365-linux/releases/download/v1.0.0"
declare -A ASSETS=(
   ["winecx.zip"]="4835f40619af3d44b49e313d5eabfdb3442c15025d3d79d62760c9532bc58656"
  ["Requerimientos-Office-2016.zip"]="2088b46518ab3095c649f8a16197bf33de3a9b9fbc4c199db10bcc310ef0ebf1"
  ["FuentesOffice365.zip"]="7d2929c8e23589bb26ae6608d9ccbd37b52d50613369b3c1e3c6ff994cfb1ee6"
)

for asset in "${!ASSETS[@]}"; do
  if [ ! -f "$WORKDIR/$asset" ] || ! echo "${ASSETS[$asset]}  $WORKDIR/$asset" | sha256sum -c --status; then
    echo ">> Descargando $asset"
    curl -fL --retry 5 --retry-delay 3 --progress-bar \
      -o "$WORKDIR/$asset" "$BASE_URL/$asset"
    echo "${ASSETS[$asset]}  $WORKDIR/$asset" | sha256sum -c --status || \
      { echo "ERROR: SHA256 mismatch en $asset" >&2; exit 1; }
  fi
done

# ---------------------------------------------------------
# 3) Instalar Winecx (Wine 10 Fedora)
# ---------------------------------------------------------
echo ">> Instalando Winecx Fedora a /opt/winecx"
WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true
sudo rm -rf /opt/winecx
unzip -q -o "$WORKDIR/winecx.zip" -d /tmp/winecx-extract
sudo mv /tmp/winecx-extract/winecx /opt/
sudo chown -R root:root /opt/winecx
sudo chmod -R 755 /opt/winecx
rm -rf /tmp/winecx-extract

WINE_VER=$(/opt/winecx/bin/wine --version 2>&1 || echo "FAILED")
echo ">> Wine: $WINE_VER"

# ---------------------------------------------------------
# 4) Crear prefix Office 2016 + Windows 7 mode
# ---------------------------------------------------------
echo ">> Creando prefix $PREFIX (Windows 7)"
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine wineboot 2>&1 | tail -3 || true
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine winecfg -v win7 2>&1 | tail -3 || true

# ---------------------------------------------------------
# 5) Dependencias wine (winetricks)
# ---------------------------------------------------------
echo ">> Instalando deps wine (corefonts, vcrun, dotnet48, etc.) - puede tardar 15+ min"
WINEPREFIX="$PREFIX" winetricks -q corefonts msxml6 riched20 riched30 gdiplus vb6run 2>&1 | tail -3 || true
WINEPREFIX="$PREFIX" winetricks -q vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 2>&1 | tail -3 || true
WINEPREFIX="$PREFIX" winetricks -q dotnet48 vcrun2015 2>&1 | tail -3 || true
WINEPREFIX="$PREFIX" winetricks --force -q vcrun2019 2>&1 | tail -3 || true
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine winecfg -v win7 2>/dev/null || true
WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true

# ---------------------------------------------------------
# 6) Descomprimir ISO Office 2016
# ---------------------------------------------------------
echo ">> Extrayendo ISO Office 2016"
ISO_OUTDIR="${ISO_FILE%.iso}"
ISO_OUTDIR="${ISO_OUTDIR%.ISO}"
[ -d "$ISO_OUTDIR" ] || 7z x "$ISO_FILE" -o"$ISO_OUTDIR" -y 2>&1 | tail -3

# ---------------------------------------------------------
# 7) Ejecutar instalador de Office (INTERACTIVO)
# ---------------------------------------------------------
echo
echo "============================================="
echo "  INSTALACIÓN INTERACTIVA DE OFFICE 2016"
echo "============================================="
echo "Va a abrirse el setup.exe de Office 2016."
echo "Sigue los pasos en pantalla. Cuando termine, vuelve a esta terminal."
echo
read -r -p "Pulsa ENTER para abrir el setup..." </dev/tty

export WINEPREFIX="$PREFIX"
export PATH="/opt/winecx/bin:$PATH"

WINEPREFIX="$PREFIX" /opt/winecx/bin/wine "$ISO_OUTDIR/setup.exe" || true

echo
read -r -p "Cuando termine la instalación de Office, pulsa ENTER..." </dev/tty

echo
echo "Ahora se abrirá Excel para inicializar la configuración."
echo "Cierra Excel cuando cargue completamente."
read -r -p "Pulsa ENTER para abrir Excel..." </dev/tty

WINEPREFIX="$PREFIX" /opt/winecx/bin/wine \
  "C:\\Program Files (x86)\\Microsoft Office\\Office16\\EXCEL.EXE" >/dev/null 2>&1 || true

read -r -p "Cuando hayas cerrado Excel, pulsa ENTER..." </dev/tty

# ---------------------------------------------------------
# 8) Descomprimir Requerimientos + Gecko/Mono + DLL OSPP
# ---------------------------------------------------------
echo ">> Instalando Requerimientos Office 2016"
REQ_DIR="$WORKDIR/Requerimientos Office 2016"
rm -rf "$REQ_DIR"
unzip -q -o "$WORKDIR/Requerimientos-Office-2016.zip" -d "$WORKDIR"

cd "$REQ_DIR"
unzip -q -o "Office 2016 icons.zip"
unzip -q -o "OfficeSoftwareProtectionPlatform.zip"

echo ">> Gecko + Mono (system-wide)"
sudo mkdir -p /usr/share/wine/gecko /usr/share/wine/mono
sudo cp wine-gecko-2.47.4-x86*.msi /usr/share/wine/gecko/
sudo cp wine-mono-9.4.0-x86.msi    /usr/share/wine/mono/

WINEPREFIX="$PREFIX" /opt/winecx/bin/wine reg add \
  "HKLM\\Software\\Wine\\Gecko" /v Version /t REG_SZ /d "2.47.4" /f 2>/dev/null
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine reg add \
  "HKLM\\Software\\Wine\\Mono"  /v Version /t REG_SZ /d "9.4.0"  /f 2>/dev/null

echo ">> Aplicando correcciones DirectX/Direct2D"
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine reg add \
  "HKCU\\Software\\Wine\\Direct2D" /v max_version_factory /t REG_DWORD /d 0 /f 2>/dev/null
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine reg add \
  "HKCU\\Software\\Wine\\Direct3D" /v MaxVersionGL /t REG_DWORD /d 0x30002 /f 2>/dev/null

echo ">> Inyectando DLL OSPP (necesario para activador)"
OSPP_DEST="$PREFIX/drive_c/Program Files (x86)/Common Files/Microsoft Shared/OfficeSoftwareProtectionPlatform"
mkdir -p "$OSPP_DEST"
cp "$REQ_DIR/OfficeSoftwareProtectionPlatform/"OSPPC.DLL "$OSPP_DEST/" 2>/dev/null || true
cp "$REQ_DIR/OfficeSoftwareProtectionPlatform/"OSPPCEXT.DLL "$OSPP_DEST/" 2>/dev/null || true
cp "$REQ_DIR/OfficeSoftwareProtectionPlatform/"sppcs.dll "$OSPP_DEST/" 2>/dev/null || true
cp "$REQ_DIR/OfficeSoftwareProtectionPlatform/"sppcs.dll \
   "$PREFIX/drive_c/Program Files (x86)/Microsoft Office/Office16/" 2>/dev/null || true

# ---------------------------------------------------------
# 9) Íconos + fuentes
# ---------------------------------------------------------
echo ">> Íconos"
sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
sudo cp "$REQ_DIR/Office 2016 icons/"*.png /usr/share/icons/hicolor/256x256/apps/ 2>/dev/null || true
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true

echo ">> Fuentes"
rm -rf "$WORKDIR/FuentesOffice365"
unzip -q -o "$WORKDIR/FuentesOffice365.zip" -d "$WORKDIR"
mkdir -p "$PREFIX/drive_c/windows/Fonts"
cp "$WORKDIR/FuentesOffice365/"*.ttf "$PREFIX/drive_c/windows/Fonts/" 2>/dev/null || true
cp "$WORKDIR/FuentesOffice365/"*.TTF "$PREFIX/drive_c/windows/Fonts/" 2>/dev/null || true
cp "$WORKDIR/FuentesOffice365/"*.ttc "$PREFIX/drive_c/windows/Fonts/" 2>/dev/null || true
sudo mkdir -p /usr/share/fonts/Windows
sudo cp "$WORKDIR/FuentesOffice365/"*.ttf /usr/share/fonts/Windows/ 2>/dev/null || true
sudo cp "$WORKDIR/FuentesOffice365/"*.TTF /usr/share/fonts/Windows/ 2>/dev/null || true
sudo cp "$WORKDIR/FuentesOffice365/"*.ttc /usr/share/fonts/Windows/ 2>/dev/null || true
sudo fc-cache -f 2>/dev/null || true

WINEPREFIX="$PREFIX" bash -c '
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
/opt/winecx/bin/wine regedit "$REGFILE" 2>/dev/null || true
'

# ---------------------------------------------------------
# 10) Launchers + .desktop (Office 2016 path)
# ---------------------------------------------------------
echo ">> Lanzadores"
sudo mkdir -p /opt/wine/launchers
sudo chmod 755 /opt/wine/launchers

create_launcher2016() {
  local name="$1" exe="$2"
  sudo tee "/opt/wine/launchers/${name}.sh" > /dev/null <<EOF
#!/bin/bash
export WINEPREFIX="\$HOME/.office2016"
export PATH="/opt/winecx/bin:\$PATH"
export LANG=C.UTF-8
export WINEDEBUG=-all
app="C:\\\\Program Files (x86)\\\\Microsoft Office\\\\Office16\\\\${exe}"
/opt/winecx/bin/wineserver -p >/dev/null 2>&1 || true
if [ \$# -eq 0 ]; then exec /opt/winecx/bin/wine "\$app"
else for f in "\$@"; do /opt/winecx/bin/wine "\$app" "Z:\${f//\//\\\\}"; done; fi
EOF
  sudo chmod +x "/opt/wine/launchers/${name}.sh"
}

create_desktop2016() {
  local name="$1" display="$2" icon="$3" cats="$4" mime="$5" wmclass="$6"
  sudo tee "/usr/share/applications/${name}.desktop" > /dev/null <<EOF
[Desktop Entry]
Name=${display}
Exec=/opt/wine/launchers/${name}.sh %F
Type=Application
Icon=${icon}
StartupWMClass=${wmclass}
Terminal=false
Categories=${cats}
MimeType=${mime}
EOF
}

create_launcher2016 "word2016"        "WINWORD.EXE"
create_desktop2016  "word2016"        "Microsoft Word 2016"       "word2016"       "Office;WordProcessor;" \
  "application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;" "winword.exe"

create_launcher2016 "excel2016"       "EXCEL.EXE"
create_desktop2016  "excel2016"       "Microsoft Excel 2016"      "excel2016"      "Office;Spreadsheet;" \
  "application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;text/csv;" "excel.exe"

create_launcher2016 "powerpoint2016"  "POWERPNT.EXE"
create_desktop2016  "powerpoint2016"  "Microsoft PowerPoint 2016" "powerpoint2016" "Office;Presentation;" \
  "application/vnd.ms-powerpoint;application/vnd.openxmlformats-officedocument.presentationml.presentation;" "powerpnt.exe"

create_launcher2016 "outlook2016"     "OUTLOOK.EXE"
create_desktop2016  "outlook2016"     "Microsoft Outlook 2016"    "outlook2016"    "Office;Email;" \
  "application/vnd.ms-outlook;message/rfc822;" "outlook.exe"

create_launcher2016 "access2016"      "MSACCESS.EXE"
create_desktop2016  "access2016"      "Microsoft Access 2016"     "access2016"     "Office;Database;" \
  "application/vnd.ms-access;application/x-msaccess;" "msaccess.exe"

create_launcher2016 "publisher2016"   "MSPUB.EXE"
create_desktop2016  "publisher2016"   "Microsoft Publisher 2016"  "publisher2016"  "Office;Publishing;" \
  "application/x-mspublisher;" "mspub.exe"

# Corregir asociaciones Excel
cat > /tmp/fix_excel_associations.reg <<'EOF'
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\.xls]
@="Excel.Sheet.8"

[HKEY_CLASSES_ROOT\.xlsx]
@="Excel.Sheet.12"

[HKEY_CLASSES_ROOT\Excel.Sheet.8\shell\Open\command]
@="\"C:\\Program Files (x86)\\Microsoft Office\\Office16\\EXCEL.EXE\" \"%1\""

[HKEY_CLASSES_ROOT\Excel.Sheet.12\shell\Open\command]
@="\"C:\\Program Files (x86)\\Microsoft Office\\Office16\\EXCEL.EXE\" \"%1\""

[HKEY_CLASSES_ROOT\Excel.Sheet.8\shell\Open\ddeexec]
@=""

[HKEY_CLASSES_ROOT\Excel.Sheet.12\shell\Open\ddeexec]
@=""
EOF
WINEPREFIX="$PREFIX" /opt/winecx/bin/wine regedit /S /tmp/fix_excel_associations.reg 2>/dev/null || true

sudo update-desktop-database /usr/share/applications 2>/dev/null || true

WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k 2>/dev/null || true

# ---------------------------------------------------------
# 11) Activación (instrucciones, NO ejecuta el activador)
# ---------------------------------------------------------
echo
echo "==============================================="
echo "  OFFICE 2016 INSTALADO"
echo "==============================================="
echo
echo "Office 2016 corre 30 días en modo evaluación."
echo "Para activación, usa tu licencia legítima o tu propio activador KMS"
echo "(este script no redistribuye herramientas de activación)."
echo
echo "Lanza Word/Excel/PowerPoint/Outlook/Access/Publisher desde tu menú."
echo "Path del prefix: $PREFIX"
