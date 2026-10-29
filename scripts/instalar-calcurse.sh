#!/usr/bin/env bash
# instalar-calcurse.sh
# Instala calcurse (calendario y organizador TUI) y registra el atajo de teclado.
#
# Atajo configurado:
#   Super+Shift+Alt+C  → abrir calcurse en terminal (par TUI del calendario web)
#
# Uso: bash instalar-calcurse.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

HYPR_BINDINGS="${HOME}/.config/hypr/bindings.lua"

# ── 1. Instalar calcurse ───────────────────────────────────────────────────────

if command -v calcurse &>/dev/null; then
    echo "  · calcurse ya está instalado ($(calcurse --version 2>&1 | head -1))"
else
    echo "  Instalando calcurse..."
    if [[ $EUID -eq 0 ]]; then
        pacman -S --needed --noconfirm calcurse
    elif command -v sudo &>/dev/null; then
        sudo pacman -S --needed --noconfirm calcurse
    else
        echo "✗ No se puede instalar calcurse sin root/sudo."
        exit 1
    fi
    echo "  ✓ calcurse instalado"
fi

# ── 2. Keybinding en Hyprland (Omarchy 4.x: bindings.lua) ─────────────────────

BINDING_BLOCK=$(cat <<'LUA'
o.bind("SUPER + SHIFT + ALT + C", "Calendar TUI", { tui = "calcurse", focus = true })
LUA
)

hypr_lua_upsert_block "$HYPR_BINDINGS" "calcurse" "$BINDING_BLOCK"
echo "  ✓ Keybinding Super+Shift+Alt+C sincronizado"

echo ""
echo "  Super+Shift+C      → Calendario web"
echo "  Super+Shift+Alt+C  → calcurse (TUI)"
