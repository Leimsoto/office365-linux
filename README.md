# Microsoft Office 365 en Linux (WineCX)

Instalador automático de **Microsoft Office 365** (Word, Excel, PowerPoint, Outlook, Access, Publisher) sobre **WineCX** para distros basadas en **Debian/Ubuntu**, **Arch/Artix** y **Fedora/RHEL**.

> Inspirado en la guía de [Formateando](https://www.youtube.com/@formateando). Empaquetado y automatizado para la comunidad.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Debian](https://img.shields.io/badge/Debian-based-A81D33?logo=debian)
![Ubuntu](https://img.shields.io/badge/Ubuntu-supported-E95420?logo=ubuntu)
![Arch](https://img.shields.io/badge/Arch-supported-1793D1?logo=archlinux)
![Artix](https://img.shields.io/badge/Artix-supported-10A0CC?logo=artixlinux)
![Fedora](https://img.shields.io/badge/Fedora-supported-294172?logo=fedora)
![Tested on Debian 13](https://img.shields.io/badge/Tested%20on-Debian%2013%20Trixie-success?logo=debian)
![Tested on Artix](https://img.shields.io/badge/Tested%20on-Artix%20runit-success?logo=artixlinux)
![Tested on CachyOS](https://img.shields.io/badge/Tested%20on-CachyOS-success?logo=archlinux)

---

## Instalación rápida (una línea)

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash
```

Modo no interactivo (CI / scripting):

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/install.sh | bash -s -- --yes
```

Flags disponibles:

| Flag | Descripción |
|------|-------------|
| `-y`, `--yes`     | No preguntar, asumir sí |
| `--keep-cache`    | Mantener archivos descargados en `~/.cache/office365-linux` |
| `--tag=vX.Y.Z`    | Usar un release concreto en lugar del más reciente fijado |
| `--no-verify`     | Omitir verificación SHA256 (no recomendado) |

---

## ¿Qué hace el instalador?

1. Verifica que estás en una distro Debian/Ubuntu compatible.
2. Pide confirmación antes de modificar el sistema.
3. Descarga assets desde **GitHub Releases**:
   - `MSO365.zip.part00.bin` (1.5 GB)
   - `MSO365.zip.part01.bin` (735 MB)
   - `winecx.deb` (225 MB)
4. Verifica **SHA256** de cada parte.
5. Reúne las partes en `MSO365.zip` (`cat` + SHA256 final).
6. Habilita `i386`, instala dependencias (`wine32`, `winetricks`, `libfreetype6:i386`, etc.).
7. Instala `winecx.deb` con `dpkg`.
8. Copia el prefix preconfigurado a `~/.Microsoft_Office_365`.
9. Crea lanzadores en `/opt/winecx/launchers/`.
10. Registra entradas `.desktop` e íconos en `/usr/share/applications/`.
11. Reconstruye `dosdevices`, registra fuentes de Office, limpia MRU.
12. Limpia el cache de descarga al terminar (a menos que uses `--keep-cache`).

Al terminar verás **Word 365**, **Excel 365**, **PowerPoint 365**, **Outlook 365**, **Access 365** y **Publisher 365** en tu menú de aplicaciones.

---

## Requisitos

- Distro **basada en Debian/Ubuntu**, **Arch/Artix** o **Fedora/RHEL** (probado en Debian 13 Trixie, Artix Linux runit, CachyOS; compatible con Manjaro, EndeavourOS, Garuda, ArcoLinux, Fedora 41+, RHEL 9+, Rocky, AlmaLinux, Nobara, Ultramarine, Bazzite).
- **5 GB de espacio libre** (2.3 GB descarga + 2.5 GB instalado).
- **Arquitectura x86_64** con soporte `multiarch i386`.
- **Conexión a internet**, `sudo` y `curl`.

---

## Uso manual (sin `curl | bash`)

```bash
# 1. Clonar el repo
git clone https://github.com/Leimsoto/office365-linux.git
cd office365-linux

# 2. Lanzar el instalador
chmod +x install.sh
./install.sh
```

O bien descargar manualmente los assets del [último release](https://github.com/Leimsoto/office365-linux/releases/latest) a `~/Descargas` y ejecutar:

```bash
cd ~/Descargas
cat MSO365.zip.part00.bin MSO365.zip.part01.bin > MSO365.zip
unzip -o MSO365.zip
bash office365-linux/scripts/instalar-office365-winecx.sh
```

---

## Desinstalación

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/uninstall.sh | bash
```

O manual:

```bash
sudo rm -rf "$HOME/.Microsoft_Office_365"
sudo rm -rf /opt/winecx
sudo rm /usr/share/applications/*365.desktop
sudo rm /usr/share/icons/hicolor/256x256/apps/*365.svg
sudo apt-get remove --purge winecx
rm -rf "$HOME/.cache/office365-linux"
```

---

## Estructura del repo

```
office365-linux/
├── install.sh                          # one-liner installer (curl | bash)
├── scripts/
│   ├── instalar-office365-winecx.sh    # instalador principal
│   └── uninstall.sh                    # desinstalador limpio
├── docs/
│   └── INSTALACION-RAPIDA.md           # guía manual paso a paso
├── LICENSE                             # GPL-3.0
└── README.md
```

Los binarios pesados (`MSO365.zip` partido y `winecx.deb`) se distribuyen como **GitHub Release assets** (no como archivos rastreados por git).

---

## Verificación de integridad

Los hashes SHA256 están embebidos en `install.sh` y se verifican automáticamente:

| Archivo | SHA256 |
|---------|--------|
| `MSO365.zip.part00.bin` | `7360442d7826da91a8c2f1cc7df05259422a507b42d503ea7a639f9385368947` |
| `MSO365.zip.part01.bin` | `3402addb7ac8e653c414894066203cf3b88e254e7aa0bb0b4340d4a409676eae` |
| `winecx.deb`            | `1196feacf0691ef461d8bf7c29e0f3ae29740b04e6d00fed1740dafaf4f19d3c` |
| `MSO365.zip` (unido)    | `a8029fdff0f30b939b56f11c05312cdf5d6ed22481a3122b130420f4260786da` |

---

## Solución de problemas

### Menú interactivo `fixes.sh`

Para todo: reparar pacman.conf en Artix, instalar fonts extra, matar procesos
colgados, re-inicializar prefix, verificar estado, limpiar cache, reinstalar.

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/fixes.sh | bash
```

Modo directo (sin menú, ejecuta la opción y sale):

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/fixes.sh | bash -s -- 2
```

| Opción | Acción |
|---|---|
| 1 | Reparar `/etc/pacman.conf` (solo Artix) |
| 2 | Instalar fonts extra (Aptos, Cascadia, Selawik, Carlito, Liberation, Noto CJK…) |
| 3 | Matar procesos Office/Wine colgados |
| 4 | Re-inicializar prefix wine (`wineboot -u`) |
| 5 | Verificar estado instalación |
| 6 | Limpiar cache de descarga |
| 7 | Desinstalar todo |
| 8 | Re-instalación limpia (desinstala + instala) |
| 9 | Reparar cache de fonts wine (cuelgues en dropdown de fonts) |
| 10 | Activar Wine virtual desktop (fix ventana transparente KDE/KWin/Wayland) |
| 11 | Desactivar Wine virtual desktop (volver a ventana nativa) |

### Atajos manuales

**Word / Excel no abre**
```bash
WINEPREFIX="$HOME/.Microsoft_Office_365" /opt/winecx/bin/wineserver -k
/opt/winecx/launchers/word365.sh
```

**Fuentes faltantes**
```bash
# Vía fixes.sh (recomendado)
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/fixes.sh | bash -s -- 2
```

**`dpkg: error: package architecture (i386) does not match`**
```bash
sudo dpkg --add-architecture i386
sudo apt-get update
```

**SHA256 mismatch al descargar**
Vuelve a correr el instalador; reanuda descargas con cache.

---

## Licencia

Código bajo **GNU GPL v3.0** — ver [LICENSE](LICENSE).

Microsoft Office, Windows y los nombres de productos relacionados son marcas registradas de Microsoft Corporation. Este repo no distribuye binarios de Microsoft; el archivo `MSO365.zip` contiene únicamente un **wine prefix preconfigurado** y fuentes. La obtención de una licencia válida de Office 365 es responsabilidad del usuario.

WineCX es una compilación derivada del proyecto Wine / CrossOver; los créditos correspondientes recaen en CodeWeavers y el proyecto Wine.

---

## Contribuir

Pull requests bienvenidos. Para cambios grandes, abre primero un issue.

Probado en:
- **Debian 13 (Trixie)** ✅ verificado end-to-end (v1.0.1)
- **Artix Linux (runit)** ✅ verificado end-to-end (v1.1.0)
- **CachyOS** ✅ verificado end-to-end (v1.1.0)
- **Fedora** ⚠️ soporte experimental (v1.2.0, en validación)
- Arch / Manjaro / EndeavourOS / Garuda (compatible vía router, mismo path Arch)
- RHEL / Rocky / AlmaLinux / Nobara / Ultramarine / Bazzite (compatible vía router, mismo path Fedora)
- Debian 12 (Bookworm)
- Ubuntu 22.04 / 24.04 LTS
- Linux Mint 21 / 22
- Pop!_OS 22.04
- MX Linux 23

---

## Contribuidores

- **[Leimar Soto](https://github.com/Leimsoto)** — Desarrollador principal · QA / testing en Debian 13 Trixie
- **[Gage](https://github.com/Gagedito)** — QA / testing en Artix Linux (runit)
- **[srwangcr](https://github.com/srwangcr)** — QA / testing en Cachy OS
