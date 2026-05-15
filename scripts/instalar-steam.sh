#!/usr/bin/env bash
# instalar-steam.sh
# Resuelve los problemas documentados e instala Steam en CachyOS.
# Ver docs/instalar-steam.pdf para el detalle de cada paso.

set -euo pipefail

# ── colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── requiere root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Este script debe ejecutarse como root (sudo $0)"
    exit 1
fi

# ── paso 1: resincronizar repositorios ───────────────────────────────────────
info "Paso 1/3: resincronizando bases de datos de repositorios..."
pacman -Syy

# ── paso 2: limpiar caché obsoleta de lib32-libxss ───────────────────────────
info "Paso 2/3: limpiando caché obsoleta de lib32-libxss..."
CACHED=( /var/cache/pacman/pkg/lib32-libxss*.pkg.tar.zst
         /var/cache/pacman/pkg/lib32-libxss*.pkg.tar.zst.sig )
removed=0
for f in "${CACHED[@]}"; do
    [[ -f "$f" ]] && { rm -f "$f"; warn "Eliminado: $f"; removed=1; }
done
[[ $removed -eq 0 ]] && info "No habia cache obsoleta de lib32-libxss."

# ── paso 3: instalar Steam ────────────────────────────────────────────────────
info "Paso 3/3: instalando Steam..."
pacman -S --needed steam

info "Steam instalado correctamente."
echo
echo "  Para usar la RTX 4060 en un juego, añade en opciones de lanzamiento:"
echo "    prime-run %command%"
echo
echo "  Para el overlay de rendimiento:"
echo "    MANGOHUD=1 prime-run %command%"
