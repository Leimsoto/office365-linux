# Instalación rápida (manual, paso a paso)

Si prefieres no usar el one-liner `curl | bash`, sigue estos pasos.

## 1. Descargar assets

Desde el [último release](https://github.com/Leimsoto/office365-linux/releases/latest), guarda en `~/Descargas`:

- `MSO365.zip.part00.bin`
- `MSO365.zip.part01.bin`
- `winecx.deb`

```bash
cd ~/Descargas
BASE="https://github.com/Leimsoto/office365-linux/releases/latest/download"
curl -fL -O "$BASE/MSO365.zip.part00.bin"
curl -fL -O "$BASE/MSO365.zip.part01.bin"
curl -fL -O "$BASE/winecx.deb"
```

## 2. Reunir y verificar

```bash
cd ~/Descargas
cat MSO365.zip.part00.bin MSO365.zip.part01.bin > MSO365.zip
sha256sum MSO365.zip
# debe ser: a8029fdff0f30b939b56f11c05312cdf5d6ed22481a3122b130420f4260786da
```

## 3. Descomprimir

```bash
unzip -o MSO365.zip
cp winecx.deb MSO365/
```

## 4. Habilitar i386 e instalar dependencias

```bash
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y build-essential gcc-multilib g++-multilib flex bison \
  git wget curl pkg-config gettext \
  cups-daemon cups-client printer-driver-all system-config-printer cups-pdf printer-driver-cups-pdf \
  msitools clang lld \
  libc6:i386 libgcc1:i386 libstdc++6:i386 \
  libfreetype6:i386 libx11-6:i386 libxext6:i386 libxrender1:i386 libxrandr2:i386 \
  winbind samba-common samba-libs gnutls-bin \
  ttf-mscorefonts-installer wine32:i386 winetricks
```

## 5. Instalar WineCX

```bash
cd ~/Descargas/MSO365
sudo dpkg -i winecx.deb || sudo apt-get install -f -y
```

## 6. Ejecutar el instalador del repo

```bash
curl -fL -O https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/instalar-office365-winecx.sh
chmod +x instalar-office365-winecx.sh
./instalar-office365-winecx.sh
```

## 7. Verificar

Busca **Word 365**, **Excel 365**, etc. en tu menú de aplicaciones.

## Desinstalar

```bash
curl -fsSL https://raw.githubusercontent.com/Leimsoto/office365-linux/main/scripts/uninstall.sh | bash
```
