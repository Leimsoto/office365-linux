#!/bin/bash
# rebuild-artix-pacman.sh — Reconstruye /etc/pacman.conf desde cero para Artix
# cuando todos los backups están dañados o vacíos.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/scripts/rebuild-artix-pacman.sh | bash

set -euo pipefail

echo "==============================================="
echo "  Rebuild /etc/pacman.conf — Artix Linux"
echo "==============================================="

. /etc/os-release 2>/dev/null || true
if [ "${ID:-}" != "artix" ]; then
  echo "ERROR: solo para Artix"
  exit 1
fi

TS=$(date +%Y%m%d-%H%M%S)
sudo cp /etc/pacman.conf "/etc/pacman.conf.preRebuild-$TS" 2>/dev/null || true
echo ">> Backup actual: /etc/pacman.conf.preRebuild-$TS"

# Escribir pacman.conf canónico de Artix
sudo tee /etc/pacman.conf >/dev/null <<'EOF'
#
# /etc/pacman.conf
#
# Reconstruido por rebuild-artix-pacman.sh

[options]
HoldPkg      = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# Repositorios nativos de Artix
[system]
Include = /etc/pacman.d/mirrorlist

[world]
Include = /etc/pacman.d/mirrorlist

[galaxy]
Include = /etc/pacman.d/mirrorlist

[lib32]
Include = /etc/pacman.d/mirrorlist
EOF

sudo chmod 644 /etc/pacman.conf
echo ">> pacman.conf base reescrito"

# Refrescar solo repos nativos
echo ">> Refrescando repos Artix"
sudo pacman -Syy --noconfirm

# Instalar artix-archlinux-support
echo ">> Instalando artix-archlinux-support"
sudo pacman -S --noconfirm --needed artix-archlinux-support

# Verificar que mirrorlist-arch existe
if [ ! -f /etc/pacman.d/mirrorlist-arch ]; then
  echo "ERROR: /etc/pacman.d/mirrorlist-arch no existe tras instalar artix-archlinux-support"
  exit 1
fi

# Añadir [extra] y [multilib] con mirrorlist-arch
sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

# Repos de Arch (vía artix-archlinux-support)
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

# Restaurar [chaotic-aur] si los archivos de soporte siguen presentes
if [ -f /etc/pacman.d/chaotic-mirrorlist ]; then
  echo ">> Detectado chaotic-mirrorlist; restaurando [chaotic-aur]"
  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  # Verificar keyring; si falta, reinstalar
  if ! sudo pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1; then
    echo ">> Recuperando keyring chaotic-aur"
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || true
    sudo pacman-key --lsign-key 3056513887B78AEB || true
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || true
  fi
else
  echo ">> chaotic-aur no detectado (no se encontró /etc/pacman.d/chaotic-mirrorlist). Skip."
fi

# Limpiar cache stale
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db
sudo rm -f /var/lib/pacman/sync/multilib.db.sig /var/lib/pacman/sync/extra.db.sig
sudo rm -f /var/lib/pacman/sync/chaotic-aur.db /var/lib/pacman/sync/chaotic-aur.db.sig

echo ">> Refrescando repos completos"
sudo pacman -Syy --noconfirm

echo ""
echo "==============================================="
echo "  pacman.conf reconstruido. Estado:"
grep -E '^\[|^Architecture' /etc/pacman.conf
echo "==============================================="
echo ""
echo "Repos sincronizados. Ahora corre:"
echo "  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/install.sh | bash"
