#!/bin/bash
# setup-keyboard-layout-switcher.sh
#
# Configura cambio de distribución de teclado US <-> Latam con Alt+` (grave)
# y agrega un indicador en la barra de Waybar.
#
# NOTA: Se usa un keybinding de Hyprland (Alt+grave) en lugar de la opción XKB
# grp:alt_shift_toggle, porque dicha opción colisiona con Shift+Alt+Tab
# (cambio de foco entre ventanas) al dispararse a nivel XKB antes de procesar Tab.
#
# Seguro de ejecutar múltiples veces (idempotente).

set -euo pipefail

HYPR_INPUT="$HOME/.config/hypr/input.conf"
HYPR_BINDINGS="$HOME/.config/hypr/bindings.conf"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
TS=$(date +%s)

# ─── 1. Hyprland: distribuciones de teclado ──────────────────────────────────

echo "==> [1/4] Configurando input.conf..."

cp "$HYPR_INPUT" "$HYPR_INPUT.bak.$TS"

# Agregar 'latam' al kb_layout (reemplaza cualquier valor anterior)
sed -i 's|^\(\s*\)kb_layout\s*=.*|\1kb_layout = us,latam|' "$HYPR_INPUT"

# Asegurar que kb_options NO incluya grp:alt_shift_toggle (usamos keybinding de
# Hyprland en su lugar para evitar conflicto con Shift+Alt+Tab)
sed -i 's|^\(\s*\)kb_options\s*=.*|\1kb_options = compose:caps|' "$HYPR_INPUT"

echo "    kb_layout y kb_options actualizados (sin grp:alt_shift_toggle)."

# ─── 2. Hyprland: keybinding Alt+grave para cambiar distribución ──────────────

echo "==> [2/4] Configurando bindings.conf..."

if grep -q 'switchxkblayout' "$HYPR_BINDINGS"; then
    echo "    Keybinding de switchxkblayout ya presente, sin cambios."
else
    cat >> "$HYPR_BINDINGS" <<'BIND'

# Cambio de distribución de teclado US <-> Latam (Alt+`)
# Se usa Alt+grave en lugar de Alt+Shift para evitar conflicto con Shift+Alt+Tab
bindd = ALT, grave, Switch keyboard layout, exec, hyprctl switchxkblayout all next
BIND
    echo "    Keybinding Alt+grave agregado."
fi

# ─── 3. Waybar: agregar módulo hyprland/language ─────────────────────────────

echo "==> [3/4] Configurando waybar config.jsonc..."

cp "$WAYBAR_CONFIG" "$WAYBAR_CONFIG.bak.$TS"

python3 - "$WAYBAR_CONFIG" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Agregar "hyprland/language" en modules-right, antes de "cpu"
if '"hyprland/language"' not in content:
    content = content.replace(
        '"pulseaudio",\n    "cpu"',
        '"pulseaudio",\n    "hyprland/language",\n    "cpu"'
    )
    print("    Módulo agregado a modules-right.")
else:
    print("    Módulo ya presente en modules-right, sin cambios.")

# Agregar bloque de configuración del módulo, antes del bloque "cpu"
if '"hyprland/language":' not in content:
    lang_block = (
        '  "hyprland/language": {\n'
        '    "format": "\u2328 {short}",\n'
        '    "tooltip-format": "Layout: {long}"\n'
        '  },\n\n  '
    )
    content = content.replace('  "cpu": {', lang_block + '"cpu": {')
    print("    Bloque de configuración del módulo agregado.")
else:
    print("    Bloque de configuración ya presente, sin cambios.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ─── 4. Waybar: estilos CSS para el indicador ────────────────────────────────

echo "==> [4/4] Configurando waybar style.css..."

if grep -q '#language' "$WAYBAR_STYLE"; then
    echo "    Estilos de #language ya presentes, sin cambios."
else
    cat >> "$WAYBAR_STYLE" <<'CSS'

#language {
  min-width: 52px;
  margin-right: 7px;
}
CSS
    echo "    Estilos de #language agregados."
fi

# ─── Aplicar cambios ──────────────────────────────────────────────────────────

echo ""
echo "==> Aplicando cambios..."

if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    sleep 0.5
    ERRORS=$(hyprctl configerrors 2>/dev/null || true)
    if [[ -n "$ERRORS" ]]; then
        echo "ADVERTENCIA: errores en la configuración de Hyprland:"
        echo "$ERRORS"
    else
        echo "    Hyprland recargado sin errores."
    fi
else
    echo "    Hyprland no está corriendo; recárgalo manualmente (Super+Shift+R)."
fi

if command -v omarchy &>/dev/null; then
    omarchy restart waybar
    echo "    Waybar reiniciado."
else
    echo "    omarchy no disponible; reinicia Waybar manualmente."
fi

echo ""
echo "Listo. Usá Alt+Shift para cambiar entre 'us' y 'latam'."
