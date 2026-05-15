#!/bin/bash
# setup-keyboard-layout-switcher.sh
#
# Configura cambio de distribución de teclado US <-> Latam con Alt+Shift
# y agrega un indicador en la barra de Waybar.
#
# Seguro de ejecutar múltiples veces (idempotente).

set -euo pipefail

HYPR_INPUT="$HOME/.config/hypr/input.conf"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
TS=$(date +%s)

# ─── 1. Hyprland: distribuciones y atajo Alt+Shift ───────────────────────────

echo "==> [1/3] Configurando input.conf..."

cp "$HYPR_INPUT" "$HYPR_INPUT.bak.$TS"

# Agregar 'latam' al kb_layout (reemplaza cualquier valor anterior)
sed -i 's|^\(\s*\)kb_layout\s*=.*|\1kb_layout = us,latam|' "$HYPR_INPUT"

# Agregar grp:alt_shift_toggle al kb_options (reemplaza cualquier valor anterior)
sed -i 's|^\(\s*\)kb_options\s*=.*|\1kb_options = compose:caps,grp:alt_shift_toggle|' "$HYPR_INPUT"

echo "    kb_layout y kb_options actualizados."

# ─── 2. Waybar: agregar módulo hyprland/language ─────────────────────────────

echo "==> [2/3] Configurando waybar config.jsonc..."

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

# ─── 3. Waybar: estilos CSS para el indicador ────────────────────────────────

echo "==> [3/3] Configurando waybar style.css..."

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

hyprctl reload
sleep 0.5
ERRORS=$(hyprctl configerrors)
if [[ -n "$ERRORS" ]]; then
    echo "ADVERTENCIA: errores en la configuración de Hyprland:"
    echo "$ERRORS"
else
    echo "    Hyprland recargado sin errores."
fi

omarchy restart waybar
echo "    Waybar reiniciado."

echo ""
echo "Listo. Usá Alt+Shift para cambiar entre 'us' y 'latam'."
