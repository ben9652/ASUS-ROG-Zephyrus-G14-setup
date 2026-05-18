#!/usr/bin/env bash
# setup-steam-shadercache-cleanup.sh
# Instala una utilidad que limpia automáticamente los shader caches de Steam
# cuando superan un umbral de tamaño.

set -euo pipefail

BINDIR="/usr/local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
UTILITY_PATH="$BINDIR/steam-shadercache-cleanup"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

run_user_systemctl() {
    local target_user="${SUDO_USER:-}"
    if [[ -n "$target_user" ]]; then
        local target_uid runtime_dir bus_addr
        target_uid="$(id -u "$target_user")"
        runtime_dir="/run/user/$target_uid"
        bus_addr="unix:path=$runtime_dir/bus"

        if [[ ! -S "$runtime_dir/bus" ]]; then
            warn "No hay bus de usuario activo para '$target_user' en $runtime_dir/bus."
            return 1
        fi

        sudo -u "$target_user" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="$bus_addr" \
            systemctl --user "$@"
    else
        systemctl --user "$@"
    fi
}

mkdir -p "$SYSTEMD_USER_DIR"

cat > "$UTILITY_PATH" << 'EOF'
#!/usr/bin/env bash
# steam-shadercache-cleanup: Sweep Steam shader caches and remove only the ones
# that exceed a size threshold.

set -euo pipefail

APPID_FILTER="${1:-}"
THRESHOLD_GIB="${2:-2}"
STEAM_HOME="${STEAM_HOME:-$HOME/.local/share/Steam}"
SHADERCACHE_DIR="$STEAM_HOME/steamapps/shadercache"

info() { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }

if [[ ! -d "$SHADERCACHE_DIR" ]]; then
    info "No Steam shader cache directory found."
    exit 0
fi

threshold_bytes=$((THRESHOLD_GIB * 1024 * 1024 * 1024))
shopt -s nullglob

for cache_dir in "$SHADERCACHE_DIR"/*; do
    [[ -d "$cache_dir" ]] || continue

    appid=$(basename "$cache_dir")
    if [[ -n "$APPID_FILTER" && "$appid" != "$APPID_FILTER" ]]; then
        continue
    fi

    size_bytes=$(du -sb "$cache_dir" | awk '{print $1}')
    info "Cache size for appid $appid: $size_bytes bytes"

    if (( size_bytes < threshold_bytes )); then
        info "Keeping cache: below threshold."
        continue
    fi

    warn "Removing cache: above threshold."
    rm -rf -- "$cache_dir"
    info "Removed $cache_dir"
done
EOF
chmod +x "$UTILITY_PATH"
info "✓ $UTILITY_PATH"

cat > "$SYSTEMD_USER_DIR/steam-shadercache-cleanup.service" << 'EOF'
[Unit]
Description=Steam shader cache cleanup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/steam-shadercache-cleanup
EOF

cat > "$SYSTEMD_USER_DIR/steam-shadercache-cleanup.timer" << 'EOF'
[Unit]
Description=Run Steam shader cache cleanup periodically

[Timer]
OnBootSec=15m
OnUnitActiveSec=12h
Persistent=true
Unit=steam-shadercache-cleanup.service

[Install]
WantedBy=timers.target
EOF

if run_user_systemctl daemon-reload && run_user_systemctl enable --now steam-shadercache-cleanup.timer; then
    info "✓ steam-shadercache-cleanup.timer habilitado"
else
    warn "No se pudo habilitar steam-shadercache-cleanup.timer ahora mismo."
    warn "Inicia sesión gráfica y ejecuta: systemctl --user daemon-reload && systemctl --user enable --now steam-shadercache-cleanup.timer"
fi

echo ""
echo "Configuración completada."
echo ""
echo "  La limpieza automática revisa todos los shader caches de Steam."
echo "  Usa un umbral de 2 GiB por defecto."