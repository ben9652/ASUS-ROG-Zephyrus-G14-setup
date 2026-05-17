#!/usr/bin/env bash
# instalar-trans.sh
# Instala la utilidad de traduccion en terminal `trans` (translate-shell).

set -euo pipefail

echo "==> Instalando trans (translate-shell)..."

if command -v trans &>/dev/null; then
    echo "    trans ya esta instalado ($(trans -V 2>/dev/null | head -1 || echo "version no detectada")), sin cambios."
else
    # En Arch/CachyOS el comando `trans` lo provee el paquete `translate-shell`.
    pacman -S --noconfirm --needed translate-shell
    echo "    trans instalado correctamente."
fi

echo ""
echo "Instalacion completada."
echo ""
echo "  Ejemplo: trans :es \"hello world\""