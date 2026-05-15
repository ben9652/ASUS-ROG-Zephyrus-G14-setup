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

HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"

# ── 1. Instalar rog-control-center si no está ─────────────────────────────────
if ! command -v rog-control-center &>/dev/null; then
    echo "  Instalando rog-control-center..."
    sudo pacman -S --noconfirm rog-control-center
    echo "  ✓ rog-control-center instalado"
else
    echo "  · rog-control-center ya está instalado"
fi

# ── 2. Keybinding en Hyprland ─────────────────────────────────────────────────
BINDING_COMMENT="# M4 / Armoury Crate button (XF86Launch1): abrir ROG Control Center"
BINDING_LINE="binddl = , XF86Launch1, ROG Control Center, exec, omarchy-launch-or-focus rog-control-center \"uwsm-app -- rog-control-center\""

if ! grep -qF "XF86Launch1" "$HYPR_BINDINGS" 2>/dev/null; then
    {
        echo ""
        echo "$BINDING_COMMENT"
        echo "$BINDING_LINE"
    } >> "$HYPR_BINDINGS"
    echo "  ✓ Binding añadido a $HYPR_BINDINGS"
else
    echo "  · Binding XF86Launch1 ya existe, no se modifica"
fi

# ── 3. Recargar Hyprland si está corriendo ────────────────────────────────────
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    echo "  ✓ Hyprland recargado"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  M4 (Armoury Crate)  →  abrir/enfocar ROG Control Center"
