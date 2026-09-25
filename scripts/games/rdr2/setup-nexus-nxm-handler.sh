#!/usr/bin/env bash
# setup-nexus-nxm-handler.sh
#
# Registra un manejador del esquema nxm:// para capturar el link que genera
# Nexus Mods al hacer click en "Mod Manager Download".
#
# ¿PARA QUÉ?
#   La API de Nexus no entrega links de descarga a cuentas free: exige el
#   "key" y "expires" del link nxm:// que la web genera en el momento. Este
#   handler guarda ese link en ~/.cache/nexus-nxm.txt y así
#   'instalar-mods-rdr2.sh' puede usarlo automáticamente (sin copiar/pegar).
#
# QUÉ HACE:
#   1. Crea ~/.local/bin/nxm-catcher (guarda el link con su timestamp).
#   2. Crea ~/.local/share/applications/nxm-handler.desktop.
#   3. Lo registra como manejador por defecto de x-scheme-handler/nxm.
#
# USO:
#   bash setup-nexus-nxm-handler.sh              # instalar
#   bash setup-nexus-nxm-handler.sh --uninstall  # desinstalar
#
# FLUJO COMPLETO (cuenta free):
#   1. bash setup-nexus-nxm-handler.sh
#   2. En nexusmods.com (logueado) → Files → click "Mod Manager Download"
#      (el navegador puede pedir confirmación la primera vez).
#   3. bash instalar-mods-rdr2.sh --nexus-api-key TU_API_KEY
#      El instalador detecta el link solo si lo usás dentro de los 15 minutos.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
CATCHER="$BIN_DIR/nxm-catcher"
APP_DIR="$HOME/.local/share/applications"
DESKTOP="$APP_DIR/nxm-handler.desktop"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$DESKTOP" "$CATCHER"
    if [[ -f "$HOME/.config/mimeapps.list" ]]; then
        sed -i '/nxm-handler\.desktop/d' "$HOME/.config/mimeapps.list"
    fi
    command -v update-desktop-database &>/dev/null && update-desktop-database "$APP_DIR" &>/dev/null || true
    info "Handler nxm desinstalado."
    exit 0
fi

if ! command -v xdg-mime &>/dev/null; then
    error "Falta 'xdg-mime' (paquete xdg-utils). Instalalo y volvé a intentar."
    exit 1
fi

mkdir -p "$BIN_DIR" "$APP_DIR"

cat > "$CATCHER" <<'EOF'
#!/usr/bin/env bash
# nxm-catcher: guarda el último link nxm:// recibido (lo usa instalar-mods-rdr2.sh)
mkdir -p "$HOME/.cache"
printf '%s\n' "${1:-}" > "$HOME/.cache/nexus-nxm.txt"
EOF
chmod +x "$CATCHER"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=NXM Link Catcher
Comment=Captura links nxm:// de Nexus Mods para cuentas free
Exec=$CATCHER %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/nxm;
EOF

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APP_DIR" 2>/dev/null || warn "update-desktop-database falló; el navegador podría preguntar qué app usar."
else
    warn "Falta update-desktop-database (paquete desktop-file-utils)."
fi
xdg-mime default nxm-handler.desktop x-scheme-handler/nxm

CURRENT="$(xdg-mime query default x-scheme-handler/nxm 2>/dev/null || true)"
if [[ "$CURRENT" == "nxm-handler.desktop" ]]; then
    info "Handler nxm instalado y registrado."
else
    warn "El registro no quedó como default (actual: ${CURRENT:-ninguno})."
    warn "Puede que el navegador pregunte qué aplicación usar la primera vez."
fi

echo ""
echo "  Flujo para bajar el mod de glyphs (cuenta free):"
echo "    1. En nexusmods.com → Files del mod → 'Mod Manager Download'"
echo "       (archivo PlayStation Icons Replacement (PS5))."
echo "    2. El link queda en ~/.cache/nexus-nxm.txt"
echo "    3. bash $(dirname "$0")/instalar-mods-rdr2.sh --nexus-api-key TU_API_KEY"
echo ""
echo "  Desinstalar: bash $0 --uninstall"
