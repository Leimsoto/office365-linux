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

# Limpiar cache stale
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db
sudo rm -f /var/lib/pacman/sync/multilib.db.sig /var/lib/pacman/sync/extra.db.sig

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
