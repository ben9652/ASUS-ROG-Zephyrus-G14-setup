#!/usr/bin/env bash
# setup-g-helper.sh
# Instala G-Helper para Linux (utajum/g-helper-linux):
# control de GPU (modo MUX), fans, batería, RGB, perfiles de rendimiento.
#
# Ref: https://github.com/utajum/g-helper-linux
#
# Uso: sudo bash setup-g-helper.sh

set -euo pipefail

# ── requiere root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "  Error: este script debe ejecutarse como root (sudo $0)"
    exit 1
fi

# ── 1. Eliminar servicio custom anterior (asus-gpu-mode-persist) si existe ────
OLD_SERVICE="asus-gpu-mode-persist"
OLD_LIBDIR="/usr/local/lib/asus-gpu-mode"
OLD_CONFIG="/etc/asus-gpu-mode"

if systemctl is-active --quiet "$OLD_SERVICE" 2>/dev/null; then
    echo "  · Deteniendo servicio anterior: $OLD_SERVICE"
    systemctl stop "$OLD_SERVICE"
fi
if systemctl is-enabled --quiet "$OLD_SERVICE" 2>/dev/null; then
    echo "  · Deshabilitando servicio anterior: $OLD_SERVICE"
    systemctl disable "$OLD_SERVICE"
fi
if [[ -f "/etc/systemd/system/${OLD_SERVICE}.service" ]]; then
    echo "  · Eliminando unit: /etc/systemd/system/${OLD_SERVICE}.service"
    rm -f "/etc/systemd/system/${OLD_SERVICE}.service"
    systemctl daemon-reload
fi
[[ -d "$OLD_LIBDIR" ]] && rm -rf "$OLD_LIBDIR" && echo "  · Eliminado $OLD_LIBDIR"
[[ -f "$OLD_CONFIG" ]] && rm -f "$OLD_CONFIG" && echo "  · Eliminado $OLD_CONFIG"

# ── 2. Instalar G-Helper para Linux ──────────────────────────────────────────
echo "  · Descargando e instalando G-Helper para Linux..."
curl -sL https://raw.githubusercontent.com/utajum/g-helper-linux/master/install/install.sh \
    | bash

echo "  ✓ G-Helper instalado en /opt/ghelper/ghelper"
echo ""
echo "  Uso:"
echo "    ghelper          # iniciar (modo gráfico, se minimiza a la bandeja del sistema)"
echo "    ghelper --help   # opciones de línea de comandos"
echo ""
echo "  El autostart se configura en ~/.config/autostart/ghelper.desktop"
