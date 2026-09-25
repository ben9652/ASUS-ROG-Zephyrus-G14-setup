#!/usr/bin/env bash
# setup-g14-power-manual.sh
# Instala la página de manual g14-power(1): referencia de comandos para
# gestión de energía y GPU en el ASUS ROG Zephyrus G14 (asusctl,
# supergfxctl y TLP).
#
# La fuente vive en docs/g14-power.1 y se instala en /usr/local/man/man1/
# (fuera del alcance de pacman), regenerando el índice con mandb.
#
# Uso: sudo bash setup-g14-power-manual.sh

set -euo pipefail

# ── requiere root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "  Error: este script debe ejecutarse como root (sudo $0)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/../docs/g14-power.1"
MAN_DIR="/usr/local/man/man1"
TARGET="$MAN_DIR/g14-power.1"

if [[ ! -f "$SOURCE" ]]; then
    echo "  Error: no se encontró la fuente del manual: $SOURCE"
    exit 1
fi

# ── 1. Instalar la página de manual ──────────────────────────────────────────
mkdir -p "$MAN_DIR"

if [[ -f "$TARGET" ]] && cmp -s "$SOURCE" "$TARGET"; then
    echo "  · g14-power.1 ya está instalado y actualizado"
else
    install -m 644 "$SOURCE" "$TARGET"
    echo "  ✓ g14-power.1 instalado en $TARGET"
fi

# ── 2. Regenerar el índice de páginas de manual ──────────────────────────────
if command -v mandb >/dev/null 2>&1; then
    mandb --quiet /usr/local/man >/dev/null 2>&1 || true
    echo "  · Índice de mandb regenerado"
fi

echo ""
echo "  Uso:"
echo "    man g14-power"
