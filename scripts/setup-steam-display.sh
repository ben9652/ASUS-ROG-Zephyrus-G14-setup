#!/usr/bin/env bash
# setup-steam-display.sh
#
# Soluciona el problema de escala de Steam en configuración multi-monitor mixta:
#   Pantalla laptop : 2880x1800 (3K), Hyprland scale=2.0
#   Monitor externo : 1920x1080 (Full HD), Hyprland scale=1.0
#
# PROBLEMA:
#   Steam es una app XWayland. Con force_zero_scaling=true (activo en Omarchy),
#   XWayland le reporta a Steam scale=1, pero Steam igual detecta el DPI físico
#   alto de la pantalla 3K y escala su UI 2x internamente. Resultado:
#     · En la laptop    → se ve pequeño (la UI 1x queda diminuta en 2880x1800)
#     · En el Full HD   → se ve enorme, excede la pantalla (la UI 2x sobre 1080p)
#
# SOLUCIÓN APLICADA:
#   1. STEAM_FORCE_DESKTOPUI_SCALING=1 en ~/.config/hypr/envs.conf
#      → Fuerza la UI de Steam a escala 1x sin auto-detección de DPI.
#   2. windowrule maxsize en ~/.config/hypr/hyprland.conf
#      → Garantiza que la ventana principal de Steam no exceda 1890x1060,
#        por si Steam tiene guardada una geometría grande de sesiones anteriores.
#   3. (Opcional) Borrado de geometría guardada de Steam
#      → Limpia el tamaño/posición almacenado para que las nuevas reglas apliquen
#        desde cero en el primer arranque tras la corrección.
#
# USO:
#   bash setup-steam-display.sh          # aplica solo los cambios de Hyprland
#   bash setup-steam-display.sh --reset  # también borra la geometría guardada
#
# Seguro de ejecutar múltiples veces (idempotente).
# Requisito: Hyprland instalado y configurado en ~/.config/hypr/

set -euo pipefail

RESET_GEOMETRY=false
[[ "${1:-}" == "--reset" ]] && RESET_GEOMETRY=true

HYPR_ENVS="$HOME/.config/hypr/envs.conf"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
STEAM_REGISTRY="$HOME/.local/share/Steam/registry.vdf"

# ── colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── validaciones ──────────────────────────────────────────────────────────────
for f in "$HYPR_ENVS" "$HYPR_CONF"; do
    if [[ ! -f "$f" ]]; then
        error "No se encontró: $f"
        error "Asegúrate de que Hyprland está configurado antes de ejecutar este script."
        exit 1
    fi
done

# ── paso 1: STEAM_FORCE_DESKTOPUI_SCALING ─────────────────────────────────────
SCALING_VAR="STEAM_FORCE_DESKTOPUI_SCALING"
if grep -q "$SCALING_VAR" "$HYPR_ENVS"; then
    info "Paso 1/3: $SCALING_VAR ya configurado en envs.conf — sin cambios."
else
    cat >> "$HYPR_ENVS" <<'EOF'

# Steam: forzar escala de UI a 1x para evitar que se vea enorme en el monitor
# Full HD cuando la pantalla de la laptop es 3K (scale=2.0).
env = STEAM_FORCE_DESKTOPUI_SCALING,1
EOF
    info "Paso 1/3: $SCALING_VAR=1 añadido a envs.conf."
fi

# ── paso 2: windowrule de tamaño ─────────────────────────────────────────────
# Omarchy ya incluye en ~/.local/share/omarchy/default/hypr/apps/steam.conf:
#   windowrule = size 1100 700, match:class steam, match:title Steam
# Con STEAM_FORCE_DESKTOPUI_SCALING=1 esa regla es suficiente.
# Solo añadimos aquí si el usuario quiere un tamaño diferente al default.
SIZE_RULE="windowrule = size 1100 700, match:class steam, match:title Steam"
if grep -qF "size.*steam.*Steam\|size.*Steam.*steam" "$HYPR_CONF" 2>/dev/null || \
   grep -q "omarchy.*steam\|steam.*omarchy" "$HYPR_CONF" 2>/dev/null; then
    info "Paso 2/3: Omarchy ya gestiona el tamaño de la ventana de Steam — sin cambios."
else
    cat >> "$HYPR_CONF" <<EOF

# Steam: tamaño fijo para la ventana principal (cabe en Full HD y en la laptop)
$SIZE_RULE
EOF
    info "Paso 2/3: Windowrule de tamaño para Steam añadida a hyprland.conf."
fi

# ── paso 3 (opcional): resetear geometría guardada ───────────────────────────
if [[ "$RESET_GEOMETRY" == true ]]; then
    if pgrep -x steam &>/dev/null; then
        warn "Paso 3/3: Steam está corriendo. Ciérralo antes de resetear la geometría."
    else
        # Steam guarda posiciones de ventana en registry.vdf (formato binario/texto)
        # La clave relevante es "width"/"height" dentro del nodo MainWindowSize
        if [[ -f "$STEAM_REGISTRY" ]]; then
            cp "$STEAM_REGISTRY" "${STEAM_REGISTRY}.bak.$(date +%s)"
            # Eliminar las entradas de geometría de la ventana principal de Steam
            sed -i \
                -e '/\"MainWindowType\"/d' \
                -e '/\"MainWindowLeft\"/d' \
                -e '/\"MainWindowTop\"/d'  \
                -e '/\"MainWindowWidth\"/d' \
                -e '/\"MainWindowHeight\"/d' \
                "$STEAM_REGISTRY"
            info "Paso 3/3: Geometría guardada de Steam reseteada (backup en ${STEAM_REGISTRY}.bak)."
        else
            warn "Paso 3/3: No se encontró registry.vdf de Steam — no había geometría que limpiar."
        fi
    fi
else
    info "Paso 3/3: Omitido. Usa --reset para borrar también la geometría guardada de Steam."
fi

# ── recarga Hyprland ──────────────────────────────────────────────────────────
echo ""
if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null 2>&1; then
    hyprctl reload
    ERRORS=$(hyprctl configerrors 2>/dev/null || true)
    if [[ -z "$ERRORS" || "$ERRORS" == "no config errors" ]]; then
        info "Hyprland recargado sin errores."
    else
        warn "Hyprland recargado con advertencias:"
        echo "$ERRORS"
    fi
else
    warn "hyprctl no disponible. Recarga Hyprland manualmente (Super+Shift+R o hyprctl reload)."
fi

echo ""
echo "  ✓ Reinicia Steam para que STEAM_FORCE_DESKTOPUI_SCALING=1 tome efecto."
echo "  · En la laptop, Steam seguirá viéndose pequeño en modo escritorio"
echo "    (lo esperado en 3K con scale=2). Usá Big Picture con el DualSense."
echo "  · En el monitor Full HD, Steam debería verse a tamaño normal."
