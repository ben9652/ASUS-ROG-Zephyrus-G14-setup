#!/usr/bin/env bash
# setup-hyprland-compat.sh
#
# Histórico: corregía dos incompatibilidades de Omarchy 3.x con Hyprland 0.48+
# editando ~/.local/share/omarchy/default/hypr/looknfeel.conf.
#
# Omarchy 4.x (Quattro) ya no usa looknfeel.conf: la configuración de Hyprland
# pasó a Lua (looknfeel.lua) y esos valores inválidos ya vienen corregidos de
# origen. Además, /usr/share/omarchy es propiedad del paquete y no debe editarse.
#
# Por eso este paso ahora es un no-op informativo: se mantiene para que
# setup.sh siga funcionando y para detectar si queda alguna instalación vieja.
#
# Uso: sudo bash setup-hyprland-compat.sh
# (invocado desde setup.sh)

set -euo pipefail

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

if [[ -f "$OMARCHY_PATH/default/hypr/looknfeel.lua" ]]; then
    echo "  · Omarchy ya usa configuración Lua (looknfeel.lua)."
    echo "  · No hay nada que parchear: los valores de Hyprland 0.48+ ya son válidos."
    echo "  · Además /usr/share/omarchy es de solo lectura (propiedad del paquete)."
    exit 0
fi

if [[ -f "$OMARCHY_PATH/default/hypr/looknfeel.conf" ]]; then
    echo "  ⚠ Se detectó una instalación vieja de Omarchy 3.x (looknfeel.conf)."
    echo "    Este repo ya apunta a Omarchy 4.x (Quattro) y no modifica archivos"
    echo "    del paquete. Actualizá Omarchy con: omarchy update"
    exit 0
fi

echo "  · No se encontró la configuración por defecto de Omarchy."
echo "    Se omite este paso."
