#!/bin/bash
# recover-artix-pacman.sh — Restaura /etc/pacman.conf desde el primer backup
# creado por fix-artix-pacman.sh y aplica los cambios mínimos correctos.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/main/scripts/recover-artix-pacman.sh | bash

set -euo pipefail

echo "==============================================="
echo "  Recover /etc/pacman.conf — Artix Linux"
echo "==============================================="

. /etc/os-release 2>/dev/null || true
if [ "${ID:-}" != "artix" ]; then
  echo "ERROR: solo para Artix"; exit 1
fi

# 1) Listar backups existentes y elegir el MAS VIEJO (original antes de nuestros scripts)
shopt -s nullglob
BACKUPS=( /etc/pacman.conf.bak-* /etc/pacman.conf.office365-bak /etc/pacman.conf.broken )
if [ ${#BACKUPS[@]} -eq 0 ]; then
  echo "ERROR: no se encontraron backups en /etc/pacman.conf.bak-* ni .office365-bak"
  exit 1
fi

echo ">> Backups encontrados:"
ls -lt /etc/pacman.conf.bak-* /etc/pacman.conf.office365-bak /etc/pacman.conf.broken 2>/dev/null || true

# Elegir el más viejo por mtime
OLDEST=$(ls -t1r /etc/pacman.conf.bak-* /etc/pacman.conf.office365-bak /etc/pacman.conf.broken 2>/dev/null | head -1)
echo ">> Restaurando desde: $OLDEST"

# Backup nuevo del estado actual antes de sobrescribir
TS=$(date +%Y%m%d-%H%M%S)
sudo cp /etc/pacman.conf "/etc/pacman.conf.preRecover-$TS"

# Restaurar
sudo cp "$OLDEST" /etc/pacman.conf
sudo chmod 644 /etc/pacman.conf

echo ">> Contenido restaurado:"
echo "------"
head -50 /etc/pacman.conf | sudo tee /dev/stderr > /dev/null
echo "------"

# 2) Sanity: si no hay [options], inyectar uno minimal
if ! grep -qE '^\[options\]' /etc/pacman.conf; then
  echo ">> [options] no existe, inyectando minimal"
  TMP=$(mktemp)
  {
    echo "[options]"
    echo "HoldPkg = pacman glibc"
    echo "Architecture = auto"
    echo "CheckSpace"
    echo "SigLevel = Required DatabaseOptional"
    echo "LocalFileSigLevel = Optional"
    echo ""
    cat /etc/pacman.conf
  } > "$TMP"
  sudo mv "$TMP" /etc/pacman.conf
  sudo chmod 644 /etc/pacman.conf
fi

# 3) Asegurar Architecture descomentada/presente
if ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
  if grep -qE '^#\s*Architecture\s*=' /etc/pacman.conf; then
    echo ">> Descomentando Architecture"
    sudo sed -i 's/^#\s*\(Architecture\s*=.*\)/\1/' /etc/pacman.conf
  else
    echo ">> Insertando Architecture = auto después de [options]"
    sudo sed -i '/^\[options\]/a Architecture = auto' /etc/pacman.conf
  fi
fi

# 4) Verificar Architecture
if ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
  echo "ERROR: no se pudo añadir Architecture. Revisar manualmente /etc/pacman.conf"
  exit 1
fi
echo ">> Architecture OK: $(grep -E '^Architecture' /etc/pacman.conf)"

# 5) Solo refrescar repos NATIVOS Artix (no tocar [multilib]/[extra] todavía)
echo ">> Refrescando repos Artix"
sudo pacman -Syy --noconfirm system world galaxy lib32 2>/dev/null || sudo pacman -Syy --noconfirm

# 6) Instalar artix-archlinux-support (provee mirrorlist-arch)
echo ">> Instalando artix-archlinux-support"
sudo pacman -S --noconfirm --needed artix-archlinux-support

# 7) Stripear cualquier [multilib]/[extra] existente y reinyectar correcto
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

sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

# 8) Limpiar cache stale
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db
sudo rm -f /var/lib/pacman/sync/multilib.db.sig /var/lib/pacman/sync/extra.db.sig

# 9) Refrescar todo
echo ">> Refrescando todos los repos (Artix + Arch)"
sudo pacman -Syy

echo ""
echo "==============================================="
echo "  pacman.conf reparado. Estado:"
grep -E '^\[|^Architecture' /etc/pacman.conf
echo "==============================================="
echo ""
echo "Ahora corre el instalador con SHA pinneado:"
echo "  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-debian/78ec798/install.sh | bash"
