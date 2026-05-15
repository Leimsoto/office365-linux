#!/bin/bash
# Instalador Office 365 + WineCX para distros basadas en Debian/Ubuntu.
# Esperado: directorio MSO365/ desempaquetado y winecx.deb dentro.
# Puede ejecutarse standalone desde $HOME/Descargas o invocado por install.sh.

set -e
set -o pipefail

echo "==============================================="
echo "  Instalador automático Office 365 - WineCX"
echo "==============================================="

# ---------------------------------------------------------
# 1) Ubicar carpeta MSO365 (Descargas por defecto)
# ---------------------------------------------------------
WORKDIR="${OFFICE365_WORKDIR:-$HOME/Descargas}"
cd "$WORKDIR"

# ---------------------------------------------------------
# 2) Descomprimir MSO365.zip si la carpeta no existe
# ---------------------------------------------------------
if [ ! -d "MSO365" ]; then
  [ -f "MSO365.zip" ] || { echo "ERROR: falta MSO365.zip en $WORKDIR" >&2; exit 1; }
  unzip -o MSO365.zip
fi

cd "$WORKDIR/MSO365"

# ---------------------------------------------------------
# 3) Habilitar arquitectura i386 + repos contrib/non-free
# ---------------------------------------------------------
sudo dpkg --add-architecture i386

# Activar contrib y non-free si no están. ttf-mscorefonts-installer vive en contrib.
# Debian 12+ usa .sources (deb822); Debian 11 y derivados aún usan sources.list clásico.
ACTIVATED_REPOS=0
if [ -d /etc/apt/sources.list.d ] && ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then
  for f in /etc/apt/sources.list.d/*.sources; do
    if grep -q "^Components:" "$f" && ! grep -q "contrib" "$f"; then
      sudo sed -i 's/^\(Components:.*\)$/\1 contrib non-free non-free-firmware/' "$f"
      ACTIVATED_REPOS=1
    fi
  done
fi
if [ -f /etc/apt/sources.list ] && ! grep -qE '\bcontrib\b' /etc/apt/sources.list; then
  sudo sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
  ACTIVATED_REPOS=1
fi
[ "$ACTIVATED_REPOS" = "1" ] && echo ">> Activado contrib / non-free / non-free-firmware"

sudo apt-get update

# ---------------------------------------------------------
# 4) Dependencias
# ---------------------------------------------------------
sudo apt-get install -y build-essential gcc-multilib g++-multilib flex bison || true
sudo apt-get install -y git wget curl pkg-config gettext || true
sudo apt-get install -y cups-daemon cups-client printer-driver-all system-config-printer cups-pdf printer-driver-cups-pdf || true
sudo apt-get install -y msitools || true
sudo apt-get install -y clang lld || true
sudo apt-get install -y libc6:i386 libgcc1:i386 libstdc++6:i386 || true
sudo apt-get install -y libfreetype6:i386 libx11-6:i386 libxext6:i386 libxrender1:i386 libxrandr2:i386 || true
sudo apt-get install -y winbind samba-common samba-libs gnutls-bin || true
sudo apt-get install -y ttf-mscorefonts-installer || true
sudo apt-get install -y wine32:i386 winetricks || true

# ---------------------------------------------------------
# 5) Instalar WineCX
# ---------------------------------------------------------
sudo dpkg -i winecx.deb || true
sudo apt-get install -f -y || true

# ---------------------------------------------------------
# 6) Copiar prefix al HOME
# ---------------------------------------------------------
if [ -d ".Microsoft_Office_365" ]; then
  cp -r .Microsoft_Office_365 "$HOME"
else
  echo "ERROR: prefix .Microsoft_Office_365 no encontrado dentro de MSO365/" >&2
  exit 1
fi

# ---------------------------------------------------------
# 7) Íconos
# ---------------------------------------------------------
sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
sudo cp Office2016Icons/*365.svg /usr/share/icons/hicolor/256x256/apps/
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true

# ---------------------------------------------------------
# 8) Carpeta de lanzadores
# ---------------------------------------------------------
sudo mkdir -p /opt/winecx/launchers
sudo chmod 755 /opt/winecx/launchers

# ---------------------------------------------------------
# 9) Función para crear lanzadores
# ---------------------------------------------------------
create_launcher() {
  local name="$1"
  local exe="$2"

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

# ---------------------------------------------------------
# 10) Lanzadores Office
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# 11) Refrescar base de datos de aplicaciones + asociaciones MIME
# ---------------------------------------------------------
sudo update-desktop-database /usr/share/applications || true

# Asociar tipos de archivo a los lanzadores (doble-click abre la app correcta)
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
# 12) Permisos del prefix
# ---------------------------------------------------------
sudo chown -R "$USER:$USER" "$HOME/.Microsoft_Office_365"
sudo chmod -R u+rwX "$HOME/.Microsoft_Office_365"

# ---------------------------------------------------------
# 13) DOSDEVICES
# ---------------------------------------------------------
rm -rf "$HOME/.Microsoft_Office_365/dosdevices"
mkdir -p "$HOME/.Microsoft_Office_365/dosdevices"
ln -s ../drive_c "$HOME/.Microsoft_Office_365/dosdevices/c:"
ln -s /          "$HOME/.Microsoft_Office_365/dosdevices/z:"
ln -s /dev/null  "$HOME/.Microsoft_Office_365/dosdevices/c::"
ln -s /dev/null  "$HOME/.Microsoft_Office_365/dosdevices/z::"
ln -s /media     "$HOME/.Microsoft_Office_365/dosdevices/d:"
ln -s "$HOME"    "$HOME/.Microsoft_Office_365/dosdevices/e:"

# ---------------------------------------------------------
# 14) Carpetas de usuario Crossover
# ---------------------------------------------------------
mkdir -p "$HOME/.Microsoft_Office_365/drive_c/users/crossover/AppData/Local"
mkdir -p "$HOME/.Microsoft_Office_365/drive_c/users/crossover/AppData/Roaming"

# ---------------------------------------------------------
# 15) wineboot -u
# ---------------------------------------------------------
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine wineboot -u || true

# ---------------------------------------------------------
# 16) Cerrar wineserver limpio (wineboot -e termina apps, luego -k mata server)
# ---------------------------------------------------------
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wine wineboot -e || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k || true
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -w || true

# ---------------------------------------------------------
# 17) Copiar fuentes de Office (a prefix Y a /usr/share/fonts/Windows)
# ---------------------------------------------------------
mkdir -p "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts"
if [ -d "$WORKDIR/MSO365/Fuentes Office365" ]; then
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttf "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.TTF "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true
  cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttc "$HOME/.Microsoft_Office_365/drive_c/windows/Fonts/" 2>/dev/null || true

  # Instalar también a nivel de sistema para LibreOffice/Inkscape/etc.
  sudo mkdir -p /usr/share/fonts/Windows
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttf /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.TTF /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo cp "$WORKDIR/MSO365/Fuentes Office365"/*.ttc /usr/share/fonts/Windows/ 2>/dev/null || true
  sudo fc-cache -f /usr/share/fonts/Windows >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------
# 18) Registrar fuentes
# ---------------------------------------------------------
WINEPREFIX="$HOME/.Microsoft_Office_365" bash -c '
FONTDIR="$WINEPREFIX/drive_c/windows/Fonts"
REGFILE="$WINEPREFIX/allfonts.reg"

{
  echo "REGEDIT4"
  echo ""
  echo "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]"
  for f in "$FONTDIR"/*.ttf "$FONTDIR"/*.TTF "$FONTDIR"/*.otf "$FONTDIR"/*.OTF; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      name="${base%.*}"
      label=$(echo "$name" | sed "s/_/ /g" | sed "s/Regular//g" )
      echo "\"$label (TrueType)\"=\"${base}\""
  done
} > "$REGFILE"

/opt/winecx/bin/wine regedit "$REGFILE" || true
'

# ---------------------------------------------------------
# 19) Limpiar MRU
# ---------------------------------------------------------
PREFIX="$HOME/.Microsoft_Office_365"
WINEPREFIX="$PREFIX" /opt/winecx/bin/wineserver -k || true
sleep 2

if [ -f "$PREFIX/user.reg" ]; then
  sed -i '/File MRU/,+20d'  "$PREFIX/user.reg"
  sed -i '/Place MRU/,+20d' "$PREFIX/user.reg"
  sed -i '/User MRU/,+20d'  "$PREFIX/user.reg"
fi

echo "==============================================="
echo "  Office 365 instalado correctamente"
echo "==============================================="
echo
echo "Lanza Word/Excel/PowerPoint/Outlook/Access/Publisher desde tu menú de aplicaciones."
echo "Para desinstalar: bash scripts/uninstall.sh"
