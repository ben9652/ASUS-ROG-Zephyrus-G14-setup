#!/usr/bin/env bash
# setup-monitor-workspaces.sh
#
# Asigna workspaces a monitores en Hyprland:
#   Workspaces 1-2  → pantalla integrada de la laptop (eDP-1)
#   Workspaces 3-10 → monitor externo (HDMI-A-1 por defecto)
#
# El nombre del monitor externo se puede sobrescribir:
#   EXTERNAL_MONITOR=DP-1 bash setup-monitor-workspaces.sh
#
# Seguro de ejecutar múltiples veces (idempotente).
#
# Requisitos: Hyprland instalado y configurado en ~/.config/hypr/

set -euo pipefail

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
LAPTOP_MONITOR="${LAPTOP_MONITOR:-eDP-1}"
EXTERNAL_MONITOR="${EXTERNAL_MONITOR:-HDMI-A-1}"
TS=$(date +%s)

# ── Detectar monitores conectados ─────────────────────────────────────────────

echo "==> Monitores detectados por Hyprland:"
if command -v hyprctl &>/dev/null; then
    hyprctl monitors | grep "^Monitor" | awk '{print "    •", $2}'
else
    echo "    (hyprctl no disponible; usando valores por defecto)"
fi

echo ""
echo "    Laptop  : $LAPTOP_MONITOR"
echo "    Externo : $EXTERNAL_MONITOR"
echo ""
echo "    Para cambiar los nombres, usa las variables de entorno:"
echo "    LAPTOP_MONITOR=eDP-1 EXTERNAL_MONITOR=DP-1 bash $0"
echo ""

# ── Validar que hyprland.conf existe ──────────────────────────────────────────

if [[ ! -f "$HYPR_CONF" ]]; then
    echo "ERROR: No se encontró $HYPR_CONF"
    echo "       Asegúrate de que Hyprland está configurado antes de ejecutar este script."
    exit 1
fi

# ── Bloque de configuración a insertar ────────────────────────────────────────

BLOCK_MARKER="# === Asignación de workspaces por monitor ==="

BLOCK=$(cat <<EOF

$BLOCK_MARKER
# Workspaces 1-2 en la pantalla integrada de la laptop
workspace = 1, monitor:${LAPTOP_MONITOR}, default:true
workspace = 2, monitor:${LAPTOP_MONITOR}

# Workspaces 3-10 en el monitor externo
workspace = 3,  monitor:${EXTERNAL_MONITOR}, default:true
workspace = 4,  monitor:${EXTERNAL_MONITOR}
workspace = 5,  monitor:${EXTERNAL_MONITOR}
workspace = 6,  monitor:${EXTERNAL_MONITOR}
workspace = 7,  monitor:${EXTERNAL_MONITOR}
workspace = 8,  monitor:${EXTERNAL_MONITOR}
workspace = 9,  monitor:${EXTERNAL_MONITOR}
workspace = 10, monitor:${EXTERNAL_MONITOR}
EOF
)

# ── Idempotencia: reemplazar bloque si ya existe, o añadirlo ──────────────────

echo "==> [1/2] Actualizando $HYPR_CONF..."

cp "$HYPR_CONF" "$HYPR_CONF.bak.$TS"
echo "    Backup: $HYPR_CONF.bak.$TS"

if grep -qF "$BLOCK_MARKER" "$HYPR_CONF"; then
    # Eliminar el bloque anterior (desde el marcador hasta la siguiente línea vacía doble)
    python3 - "$HYPR_CONF" "$BLOCK_MARKER" <<'PYEOF'
import sys

path = sys.argv[1]
marker = sys.argv[2]

with open(path, 'r') as f:
    content = f.read()

start = content.find('\n' + marker)
if start == -1:
    start = content.find(marker)
    if start == -1:
        sys.exit(0)
else:
    start += 1  # incluir el \n previo

# Buscar el final del bloque: dos saltos de línea seguidos tras el marcador
end = content.find('\n\n', start + len(marker))
if end == -1:
    end = len(content)
else:
    end += 2  # incluir los dos \n

content = content[:start] + content[end:]

with open(path, 'w') as f:
    f.write(content)
PYEOF
    echo "    Bloque anterior eliminado."
fi

# Añadir el nuevo bloque al final
printf '%s\n' "$BLOCK" >> "$HYPR_CONF"
echo "    Bloque de workspaces añadido."

# ── Recargar Hyprland ─────────────────────────────────────────────────────────

echo ""
echo "==> [2/2] Recargando configuración de Hyprland..."

if command -v hyprctl &>/dev/null; then
    hyprctl reload
    sleep 1
    errors=$(hyprctl configerrors 2>&1)
    if [[ -z "$errors" || "$errors" == "No errors reported" ]]; then
        echo "    ✓ Configuración aplicada sin errores."
    else
        echo "    ⚠ Errores detectados en la configuración:"
        echo "$errors" | sed 's/^/      /'
        echo ""
        echo "    Puedes revertir con:"
        echo "    cp $HYPR_CONF.bak.$TS $HYPR_CONF && hyprctl reload"
    fi
else
    echo "    hyprctl no disponible. Recarga Hyprland manualmente."
fi

echo ""
echo "==> Listo."
echo ""
echo "    Workspaces 1-2  → $LAPTOP_MONITOR  (pantalla laptop)"
echo "    Workspaces 3-10 → $EXTERNAL_MONITOR (monitor externo)"
echo ""
echo "    Si el monitor externo no está conectado, Hyprland asignará"
echo "    sus workspaces automáticamente al monitor disponible."
