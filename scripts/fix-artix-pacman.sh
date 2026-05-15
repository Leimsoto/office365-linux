#!/bin/bash
# fix-artix-pacman.sh — Repara /etc/pacman.conf en Artix tras un intento fallido
# del instalador de Office 365 que dejó bloques [multilib]/[extra] mal configurados
# (apuntando a /etc/pacman.d/mirrorlist en lugar de /etc/pacman.d/mirrorlist-arch).
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/scripts/fix-artix-pacman.sh | bash

set -euo pipefail

echo "==============================================="
echo "  Fix /etc/pacman.conf — Artix Linux"
echo "==============================================="

if [ ! -f /etc/pacman.conf ]; then
  echo "ERROR: /etc/pacman.conf no existe" >&2
  exit 1
fi

. /etc/os-release 2>/dev/null || true
if [ "${ID:-}" != "artix" ]; then
  echo ">> Distro detectada: ${PRETTY_NAME:-desconocida}"
  echo ">> Este fix está pensado solo para Artix. Aborto por seguridad."
  exit 1
fi

# Backup
TS=$(date +%Y%m%d-%H%M%S)
sudo cp /etc/pacman.conf "/etc/pacman.conf.bak-$TS"
echo ">> Backup: /etc/pacman.conf.bak-$TS"

# Asegurar artix-archlinux-support (provee mirrorlist-arch)
sudo pacman -Sy --noconfirm 2>/dev/null || true
sudo pacman -S --noconfirm --needed artix-archlinux-support || true

# Stripear bloques [multilib] y [extra] existentes (puede haber duplicados o rotos)
TMP=$(mktemp)
sudo awk '
  BEGIN { skip = 0 }
  /^\[multilib\]/ { skip = 1; next }
  /^\[extra\]/    { skip = 1; next }
  /^\[/           { skip = 0 }
  !skip           { print }
' /etc/pacman.conf > "$TMP"
sudo mv "$TMP" /etc/pacman.conf
sudo chmod 644 /etc/pacman.conf

# Reinyectar bloques correctos con mirrorlist-arch
sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

# Limpiar DBs en cache (forzar redownload)
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db
sudo rm -f /var/lib/pacman/sync/multilib.db.sig /var/lib/pacman/sync/extra.db.sig

# Refrescar
echo ">> Refrescando bases de datos"
sudo pacman -Syy

echo ""
echo "==============================================="
echo "  Pacman.conf reparado. Ya puedes correr:"
echo "  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/install.sh | bash"
echo "==============================================="
