#!/usr/bin/env bash
# setup-m4-rog-control.sh
# Configura el botón M4 (Armoury Crate) para abrir ROG Control Center.
#
# El botón M4 genera XF86Launch1 (keycode 148) en este modelo.
# Al pulsar M4 se abre rog-control-center; si ya está abierto, trae la ventana
# al frente (comportamiento toggle gracias a omarchy-launch-or-focus).
#
# Requisitos: asusctl, rog-control-center (se instala si falta)
#
# Uso: bash setup-m4-rog-control.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

HYPR_BINDINGS="$HOME/.config/hypr/bindings.lua"

# ── 1. Instalar rog-control-center si no está ─────────────────────────────────
if ! command -v rog-control-center &>/dev/null; then
    echo "  Instalando rog-control-center..."
    sudo pacman -S --noconfirm rog-control-center
    echo "  ✓ rog-control-center instalado"
else
    echo "  · rog-control-center ya está instalado"
fi

# ── 2. Keybinding en Hyprland (Omarchy 4.x: bindings.lua) ─────────────────────
BINDING_BLOCK=$(cat <<'LUA'
o.bind("XF86Launch1", "ROG Control Center", { launch = "rog-control-center", focus = "rog-control-center" }, { locked = true })
LUA
)

hypr_lua_upsert_block "$HYPR_BINDINGS" "m4-rog-control" "$BINDING_BLOCK"
echo "  ✓ Binding XF86Launch1 sincronizado en $HYPR_BINDINGS"

# ── 3. Recargar Hyprland si está corriendo ────────────────────────────────────
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hypr_lua_reload
    echo "  ✓ Hyprland recargado"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  M4 (Armoury Crate)  →  abrir/enfocar ROG Control Center"
