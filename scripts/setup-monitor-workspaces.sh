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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hypr-lua.sh"

HYPR_MONITORS="$HOME/.config/hypr/monitors.lua"
LAPTOP_MONITOR="${LAPTOP_MONITOR:-eDP-1}"
EXTERNAL_MONITOR="${EXTERNAL_MONITOR:-HDMI-A-1}"
TS=$(date +%s)

# ── Detectar monitores conectados ─────────────────────────────────────────────

echo "==> Monitores detectados por Hyprland:"
if command -v hyprctl &>/dev/null; then
    hyprctl monitors 2>/dev/null | grep "^Monitor" | awk '{print "    •", $2}' || true
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

# ── Validar que monitors.lua existe ───────────────────────────────────────────

if [[ ! -f "$HYPR_MONITORS" ]]; then
    echo "ERROR: No se encontró $HYPR_MONITORS"
    echo "       Asegúrate de que Omarchy 4.x está configurado antes de ejecutar este script."
    exit 1
fi

# ── Bloque de configuración a insertar (Omarchy 4.x: Lua) ─────────────────────

BLOCK=$(cat <<EOF
hl.workspace_rule({ workspace = "1", monitor = "${LAPTOP_MONITOR}", default = true })
hl.workspace_rule({ workspace = "2", monitor = "${LAPTOP_MONITOR}" })

hl.workspace_rule({ workspace = "3", monitor = "${EXTERNAL_MONITOR}", default = true })
hl.workspace_rule({ workspace = "4", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "5", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "6", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "7", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "8", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "9", monitor = "${EXTERNAL_MONITOR}" })
hl.workspace_rule({ workspace = "10", monitor = "${EXTERNAL_MONITOR}" })
EOF
)

# ── Idempotencia: reemplazar bloque si ya existe, o añadirlo ──────────────────

echo "==> [1/2] Actualizando $HYPR_MONITORS..."

cp "$HYPR_MONITORS" "$HYPR_MONITORS.bak.$TS"
echo "    Backup: $HYPR_MONITORS.bak.$TS"

hypr_lua_upsert_block "$HYPR_MONITORS" "monitor-workspaces" "$BLOCK"
echo "    Bloque de workspaces sincronizado."

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
        echo "    cp $HYPR_MONITORS.bak.$TS $HYPR_MONITORS && hyprctl reload"
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
