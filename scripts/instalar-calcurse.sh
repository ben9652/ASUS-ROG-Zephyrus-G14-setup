#!/usr/bin/env bash
# instalar-calcurse.sh
# Instala calcurse (calendario y organizador TUI) y registra el atajo de teclado.
#
# Atajo configurado:
#   Super+Shift+Alt+C  → abrir calcurse en terminal (par TUI del calendario web)
#
# Uso: bash instalar-calcurse.sh

set -euo pipefail

HYPR_BINDINGS="${HOME}/.config/hypr/bindings.conf"

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

# ── 2. Keybinding en Hyprland ─────────────────────────────────────────────────

BINDING='bindd = SUPER SHIFT ALT, C, Calendar TUI, exec, omarchy-launch-or-focus-tui calcurse'
BINDING_COMMENT='# Super+Shift+Alt+C: calendario TUI (par TUI de Super+Shift+C = calendario web)'

if [[ ! -f "$HYPR_BINDINGS" ]]; then
    echo "⚠ No se encontró $HYPR_BINDINGS — añade el binding manualmente:"
    echo "  $BINDING"
elif grep -qF 'omarchy-launch-or-focus-tui calcurse' "$HYPR_BINDINGS"; then
    echo "  · Keybinding calcurse ya presente (sin cambios)"
else
    printf '\n%s\n%s\n' "$BINDING_COMMENT" "$BINDING" >> "$HYPR_BINDINGS"
    echo "  ✓ Keybinding Super+Shift+Alt+C añadido"
fi

echo ""
echo "  Super+Shift+C      → Calendario web"
echo "  Super+Shift+Alt+C  → calcurse (TUI)"
