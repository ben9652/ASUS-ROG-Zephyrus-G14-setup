#!/usr/bin/env bash
# setup-hyprland-compat.sh
#
# Corrige incompatibilidades entre Omarchy 3.x y Hyprland 0.48+
# presentes en el archivo de configuración por defecto de Omarchy:
#
#   ~/.local/share/omarchy/default/hypr/looknfeel.conf
#
# Problemas que resuelve:
#
#   1. col.border_locked_active  = -1   → valor de color inválido en Hyprland ≥ 0.48
#      col.border_locked_inactive = -1     (antes significaba "heredar"; ya no se acepta)
#
#   2. dwindle { pseudotile = true }    → opción eliminada en Hyprland ≥ 0.48
#
# El script es idempotente: puede ejecutarse varias veces sin efecto adicional.
# Si Omarchy se actualiza y corrige estos errores en origen, el script simplemente
# no encontrará las cadenas a reemplazar y no modificará nada.
#
# Uso: sudo bash setup-hyprland-compat.sh
# (invocado desde setup.sh)

set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
LOOKNFEEL="$REAL_HOME/.local/share/omarchy/default/hypr/looknfeel.conf"

# ── Verificar que Omarchy está instalado ──────────────────────────────────────

if [[ ! -f "$LOOKNFEEL" ]]; then
    echo "  ✗ No se encontró $LOOKNFEEL"
    echo "    ¿Está instalado Omarchy? Omite este paso."
    exit 0
fi

echo "==> [1/2] Corrigiendo colores de borde de grupos (col.border_locked_*)..."

CHANGED_COLORS=0

if grep -qF 'col.border_locked_active = -1' "$LOOKNFEEL"; then
    sed -i 's/col\.border_locked_active = -1/col.border_locked_active = $activeBorderColor/' "$LOOKNFEEL"
    echo "    ✓ col.border_locked_active  : -1  →  \$activeBorderColor"
    CHANGED_COLORS=1
else
    echo "    ✓ col.border_locked_active ya tiene un valor válido, sin cambios."
fi

if grep -qF 'col.border_locked_inactive = -1' "$LOOKNFEEL"; then
    sed -i 's/col\.border_locked_inactive = -1/col.border_locked_inactive = $inactiveBorderColor/' "$LOOKNFEEL"
    echo "    ✓ col.border_locked_inactive: -1  →  \$inactiveBorderColor"
    CHANGED_COLORS=1
else
    echo "    ✓ col.border_locked_inactive ya tiene un valor válido, sin cambios."
fi

echo "==> [2/2] Eliminando opción eliminada 'pseudotile' del bloque dwindle..."

if grep -qE '^\s*pseudotile\s*=' "$LOOKNFEEL"; then
    # Comentar la línea para dejar trazabilidad de qué se tocó
    sed -i '/^\s*pseudotile\s*=/s/^/# [compat] /' "$LOOKNFEEL"
    echo "    ✓ Línea 'pseudotile' comentada (opción eliminada en Hyprland ≥ 0.48)."
else
    echo "    ✓ Línea 'pseudotile' no encontrada o ya corregida, sin cambios."
fi

# ── Recargar si Hyprland está corriendo ──────────────────────────────────────

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    sudo -u "$REAL_USER" hyprctl reload &>/dev/null && \
        echo "    ✓ Hyprland recargado sin errores." || \
        echo "    ⚠  hyprctl reload falló; recarga manualmente con: hyprctl reload"
fi

echo ""
echo "Compatibilidad Omarchy ↔ Hyprland corregida."
echo "  Los errores de arranque 'failed to parse -1 as a color' y"
echo "  'config option <dwindle:pseudotile> does not exist' ya no aparecerán."
echo ""
echo "  Nota: si ejecutas 'omarchy update' en el futuro, vuelve a correr"
echo "  este script por si la actualización sobreescribe looknfeel.conf."
