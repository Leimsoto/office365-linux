#!/bin/bash
# fix-arch-gnutls-deps.sh — Instala las deps 32-bit que libgnutls/libnettle
# bundled de WineCX necesitan en runtime. Síntoma sin estas deps:
#
#   err:winediag:gnutls_process_attach failed to load libgnutls,
#       no support for encryption
#   err:winediag:process_attach Failed to load libgnutls, secure
#       connections will not be available.
#   (Office se queda colgado al abrir Word/Excel/etc.)
#
# Uso (en Arch/Artix/EndeavourOS/Manjaro/CachyOS/Garuda):
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/fix-arch-gnutls-deps.sh | bash

set -euo pipefail

echo "==============================================="
echo "  Fix: instalar deps 32-bit de libgnutls/libnettle"
echo "==============================================="

. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
  arch|manjaro|endeavouros|cachyos|garuda|artix|arcolinux|reborn|chimera) ;;
  *)
    echo "ERROR: este fix es para distros Arch-based (detectado: ${PRETTY_NAME:-?})"
    exit 1
    ;;
esac

# Asegurar multilib registrado
if ! pacman -Sl multilib >/dev/null 2>&1; then
  echo "ERROR: [multilib] no está habilitado en /etc/pacman.conf."
  echo "       Corre primero: curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/repair-artix-pacman.sh | bash"
  echo "       (o habilita [multilib] manualmente)"
  exit 1
fi

echo ">> Sincronizando bases de datos"
sudo pacman -Sy --noconfirm

echo ">> Instalando deps 32-bit de gnutls/nettle"
sudo pacman -S --noconfirm --needed \
  lib32-libtasn1 lib32-libidn2 lib32-p11-kit lib32-gmp lib32-libunistring \
  lib32-libnghttp2 lib32-libgpg-error lib32-libgcrypt

# Verificación: ldd sobre la libgnutls bundled
if [ -f /opt/winecx/lib32/libgnutls.so.30 ]; then
  echo ""
  echo ">> Verificación ldd sobre /opt/winecx/lib32/libgnutls.so.30 :"
  echo "------"
  LD_LIBRARY_PATH=/opt/winecx/lib32 ldd /opt/winecx/lib32/libgnutls.so.30 | grep -E "not found|=>" | head -15
  echo "------"
  if LD_LIBRARY_PATH=/opt/winecx/lib32 ldd /opt/winecx/lib32/libgnutls.so.30 | grep -q "not found"; then
    echo ""
    echo "[WARN] Aún hay libs 'not found'. Pega esta salida en el issue."
  else
    echo ""
    echo "[ OK ] Todas las deps resueltas."
  fi
fi

# Cerrar wineserver para que el próximo lanzamiento reinicialice estado
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k 2>/dev/null || true

echo ""
echo "==============================================="
echo "  Listo. Lanza Word/Excel/etc. desde el menú."
echo "==============================================="
