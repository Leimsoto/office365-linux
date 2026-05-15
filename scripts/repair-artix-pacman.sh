#!/bin/bash
# repair-artix-pacman.sh — Repara /etc/pacman.conf en Artix automáticamente.
# Autodetecta el estado del sistema y aplica la estrategia mínima necesaria:
#   - Si [options] falta o Architecture no está definida, reconstruye base.
#   - Si [multilib]/[extra] están mal apuntados, los reinyecta con mirrorlist-arch.
#   - Preserva [chaotic-aur] si los archivos de soporte siguen en disco.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/repair-artix-pacman.sh | bash

set -euo pipefail

echo "==============================================="
echo "  Repair /etc/pacman.conf — Artix Linux"
echo "==============================================="

. /etc/os-release 2>/dev/null || true
if [ "${ID:-}" != "artix" ]; then
  echo "ERROR: este script es solo para Artix Linux."
  echo "       Distro detectada: ${PRETTY_NAME:-desconocida}"
  exit 1
fi

TS=$(date +%Y%m%d-%H%M%S)
sudo cp /etc/pacman.conf "/etc/pacman.conf.preRepair-$TS" 2>/dev/null || true
echo ">> Backup actual: /etc/pacman.conf.preRepair-$TS"

# ---- 1) Detectar nivel de daño ----
HAS_OPTIONS=0
HAS_NATIVE=0
HAS_ARCH=0
ARCH_OK=0
NEEDS_REBUILD=0

grep -qE '^\[options\]'                  /etc/pacman.conf && HAS_OPTIONS=1
grep -qE '^\[(system|world|galaxy|lib32)\]' /etc/pacman.conf && HAS_NATIVE=1
grep -qE '^\[(extra|multilib)\]'         /etc/pacman.conf && HAS_ARCH=1
grep -qE '^Architecture\s*='             /etc/pacman.conf && ARCH_OK=1

# Si falta [options] o repos nativos, hay que rebuild completo
[ "$HAS_OPTIONS" -eq 0 ] && NEEDS_REBUILD=1
[ "$HAS_NATIVE"  -eq 0 ] && NEEDS_REBUILD=1

echo ">> Estado: options=$HAS_OPTIONS native=$HAS_NATIVE arch=$HAS_ARCH arch_set=$ARCH_OK"

# ---- 2) Rebuild base si es necesario ----
if [ "$NEEDS_REBUILD" -eq 1 ]; then
  echo ">> Reconstruyendo pacman.conf canónico Artix"
  sudo tee /etc/pacman.conf >/dev/null <<'EOF'
#
# /etc/pacman.conf
# Reconstruido por repair-artix-pacman.sh

[options]
HoldPkg      = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

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
fi

# ---- 3) Asegurar Architecture ----
if [ "$ARCH_OK" -eq 0 ] && ! grep -qE '^Architecture\s*=' /etc/pacman.conf; then
  if grep -qE '^#\s*Architecture\s*=' /etc/pacman.conf; then
    echo ">> Descomentando Architecture"
    sudo sed -i 's/^#\s*\(Architecture\s*=.*\)/\1/' /etc/pacman.conf
  else
    echo ">> Insertando Architecture = auto"
    sudo sed -i '/^\[options\]/a Architecture = auto' /etc/pacman.conf
  fi
fi

# ---- 4) Refrescar repos nativos antes de tocar extras ----
echo ">> Refrescando repos nativos Artix"
sudo pacman -Syy --noconfirm

# ---- 5) artix-archlinux-support (provee mirrorlist-arch) ----
echo ">> Asegurando artix-archlinux-support"
sudo pacman -S --noconfirm --needed artix-archlinux-support

if [ ! -f /etc/pacman.d/mirrorlist-arch ]; then
  echo "ERROR: mirrorlist-arch no se generó tras instalar artix-archlinux-support"
  exit 1
fi

# ---- 6) Stripear [multilib]/[extra] existentes (rotos o no) y reinyectar correctos ----
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

# ---- 7) Restaurar [chaotic-aur] si los archivos de soporte siguen presentes ----
if [ -f /etc/pacman.d/chaotic-mirrorlist ] && ! grep -qE '^\[chaotic-aur\]' /etc/pacman.conf; then
  echo ">> chaotic-mirrorlist presente, restaurando [chaotic-aur]"
  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
  if ! sudo pacman-key --list-keys 3056513887B78AEB >/dev/null 2>&1; then
    echo ">> Re-importando keyring chaotic-aur"
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || true
    sudo pacman-key --lsign-key 3056513887B78AEB || true
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || true
  fi
fi

# ---- 8) Limpiar caches stale + sync final ----
sudo rm -f /var/lib/pacman/sync/multilib.db /var/lib/pacman/sync/extra.db /var/lib/pacman/sync/chaotic-aur.db
sudo rm -f /var/lib/pacman/sync/multilib.db.sig /var/lib/pacman/sync/extra.db.sig /var/lib/pacman/sync/chaotic-aur.db.sig

echo ">> Sync final con todos los repos"
sudo pacman -Syy --noconfirm

echo ""
echo "==============================================="
echo "  pacman.conf reparado. Secciones activas:"
grep -E '^\[|^Architecture' /etc/pacman.conf
echo "==============================================="
echo ""
echo "Ahora corre el instalador Office 365:"
echo "  curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash"
