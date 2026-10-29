#!/usr/bin/env bash
# setup-keyboard-layout-switcher.sh
#
# Configura el cambio de distribución de teclado US <-> Latam con Super+` (grave)
# y asegura el indicador del idioma activo en la barra del shell de Omarchy.
#
# NOTA: Se usa un keybinding de Hyprland (Super+grave) en lugar de la opción XKB
# grp:alt_shift_toggle, porque dicha opción colisiona con Shift+Alt+Tab
# (cambio de foco entre ventanas) al dispararse a nivel XKB antes de procesar Tab.
#
# Omarchy 4.x (Quattro) usa configuración Lua en ~/.config/hypr/*.lua y el shell
# de Omarchy (Quickshell) en lugar de Waybar. El widget del idioma se llama
# `omarchy.keyboard-layout` y ya viene incluido en el catálogo del shell.
#
# Seguro de ejecutar múltiples veces (idempotente).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

HYPR_INPUT="$REAL_HOME/.config/hypr/input.lua"
HYPR_BINDINGS="$REAL_HOME/.config/hypr/bindings.lua"

run_as_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# ─── 1. Hyprland: distribuciones de teclado ──────────────────────────────────

echo "==> [1/3] Configurando input.lua..."

INPUT_BLOCK=$(cat <<'LUA'
hl.config({
  input = {
    -- Alternancia US <-> Latam con Super+grave (ver bindings.lua).
    kb_layout = "us,latam",
    kb_options = "",

    touchpad = {
      -- Scroll natural (deslizar arriba → baja el contenido).
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})
LUA
)

hypr_lua_upsert_block "$HYPR_INPUT" "keyboard-layout" "$INPUT_BLOCK"

echo "    kb_layout y kb_options actualizados (sin grp:alt_shift_toggle)."
echo "    natural_scroll activado en touchpad."

# ─── 2. Hyprland: keybinding Super+grave para cambiar distribución ────────────

echo "==> [2/3] Configurando bindings.lua..."

BINDINGS_BLOCK=$(cat <<'LUA'
o.bind("SUPER + grave", "Switch keyboard layout", "hyprctl switchxkblayout all next")
LUA
)

hypr_lua_upsert_block "$HYPR_BINDINGS" "keyboard-layout" "$BINDINGS_BLOCK"

echo "    Keybinding Super+grave asegurado."

# ─── 3. Shell de Omarchy: indicador del idioma ───────────────────────────────

echo "==> [3/3] Asegurando el widget del idioma en el shell de Omarchy..."

if command -v omarchy >/dev/null 2>&1; then
    # `omarchy bar put` es idempotente: si el widget ya está, no lo mueve.
    if run_as_user omarchy bar put omarchy.keyboard-layout --after omarchy.clock >/dev/null 2>&1; then
        echo "    Widget omarchy.keyboard-layout presente en la barra."
    else
        echo "    ⚠ No se pudo confirmar el widget; revisá el shell tras iniciar sesión."
    fi
else
    echo "    omarchy no disponible; el widget se añadirá al iniciar sesión."
fi

# ─── Aplicar cambios ──────────────────────────────────────────────────────────

echo ""
echo "==> Aplicando cambios..."

if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hypr_lua_reload
    sleep 0.5
    ERRORS=$(hypr_lua_config_errors)
    if [[ -n "$ERRORS" ]]; then
        echo "ADVERTENCIA: errores en la configuración de Hyprland:"
        echo "$ERRORS"
    else
        echo "    Hyprland recargado sin errores."
    fi
else
    echo "    Hyprland no está corriendo; recárgalo manualmente (hyprctl reload)."
fi

if command -v omarchy &>/dev/null; then
    run_as_user omarchy restart shell >/dev/null 2>&1 || true
    echo "    Shell de Omarchy reiniciado."
fi

echo ""
echo "Listo. Usá Super+\` para cambiar entre 'us' y 'latam'."
