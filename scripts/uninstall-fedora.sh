#!/bin/bash
# Desinstalador limpio de Office 365 WineCX en Fedora/RHEL/derivadas
set -e

echo "Eliminando prefix Office 365, lanzadores, íconos y entradas de menú..."

sudo rm -rf "$HOME/.Microsoft_Office_365"
sudo rm -rf /opt/winecx
sudo rm -f  /usr/share/applications/word365.desktop \
            /usr/share/applications/excel365.desktop \
            /usr/share/applications/powerpoint365.desktop \
            /usr/share/applications/outlook365.desktop \
            /usr/share/applications/access365.desktop \
            /usr/share/applications/publisher365.desktop \
            /usr/share/applications/kill_office.desktop
sudo rm -f  /usr/share/icons/hicolor/256x256/apps/Word365.svg \
            /usr/share/icons/hicolor/256x256/apps/Excel365.svg \
            /usr/share/icons/hicolor/256x256/apps/Powerpoint365.svg \
            /usr/share/icons/hicolor/256x256/apps/Outlook365.svg \
            /usr/share/icons/hicolor/256x256/apps/Access365.svg \
            /usr/share/icons/hicolor/256x256/apps/Publisher365.svg
sudo rm -rf /usr/share/fonts/Windows
sudo fc-cache -f >/dev/null 2>&1 || true
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true
sudo update-desktop-database /usr/share/applications || true

echo "Cache del instalador:"
echo "  rm -rf \"\$HOME/.cache/office365-linux\""

echo
echo "Paquetes dnf instalados como dependencia se conservan. Removerlos manualmente si quieres:"
echo "  sudo dnf remove cabextract msitools samba-winbind"
echo "  sudo dnf autoremove"

echo "Listo."
