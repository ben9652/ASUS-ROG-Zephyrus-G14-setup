#!/usr/bin/env bash
# setup-gpu-mode-persist.sh
# Instala un mecanismo de persistencia del modo GPU elegido en ROG Control Center.
#
# Contexto:
#   En el GA403UV, el modo de GPU se controla mediante el atributo del kernel
#   /sys/devices/platform/asus-nb-wmi/gpu_mux_mode:
#     0 = Ultimate   (dGPU conectada directo al panel, máx. rendimiento)
#     1 = Integrated (iGPU maneja el panel; dGPU disponible vía PRIME Offload)
#
#   asusd gestiona este valor, pero si una actualización de BIOS/firmware resetea
#   el EC (Embedded Controller), el modo vuelve al default del fabricante (0 = Ultimate)
#   y asusd arranca sin valor guardado ("No saved value for attribute gpu_mux_mode"),
#   por lo que no lo corrige automáticamente.
#
# Solución: servicio systemd con ciclo completo de arranque/apagado:
#   - ExecStart: lee /etc/asus-gpu-mode y lo aplica si el hardware derivó.
#   - ExecStop:  lee el gpu_mux_mode actual y lo guarda en /etc/asus-gpu-mode.
#
#   Al reiniciar después de cambiar el modo en ROG Control Center, el ExecStop
#   captura el nuevo modo automáticamente, sin intervención manual.
#
# Uso: sudo bash setup-gpu-mode-persist.sh

set -euo pipefail

SYSFS_MUX="/sys/devices/platform/asus-nb-wmi/gpu_mux_mode"
MODE_CONFIG="/etc/asus-gpu-mode"
SERVICE_NAME="asus-gpu-mode-persist"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LIBDIR="/usr/local/lib/asus-gpu-mode"
LIBDIR="/usr/local/lib/asus-gpu-mode"

# Tabla de nombres para mensajes legibles
declare -A MODE_NAMES=( [0]="Ultimate (dGPU)" [1]="Integrated (iGPU)" )

# ── requiere root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "  Error: este script debe ejecutarse como root (sudo $0)"
    exit 1
fi

# ── 1. Verificar que el atributo existe en este hardware ──────────────────────
if [[ ! -f "$SYSFS_MUX" ]]; then
    echo "  Error: $SYSFS_MUX no existe. ¿Está cargado el módulo asus-nb-wmi?"
    exit 1
fi

current_mode=$(cat "$SYSFS_MUX")
echo "  · Modo actual del hardware: $current_mode (${MODE_NAMES[$current_mode]:-desconocido})"

# ── 2. Guardar el modo actual como modo deseado (si no hay uno ya guardado) ───
if [[ -f "$MODE_CONFIG" ]]; then
    saved_mode=$(cat "$MODE_CONFIG")
    echo "  · Modo guardado existente: $saved_mode (${MODE_NAMES[$saved_mode]:-desconocido}) — se mantiene"
else
    echo "$current_mode" > "$MODE_CONFIG"
    saved_mode=$current_mode
    echo "  ✓ Modo guardado por primera vez: $saved_mode (${MODE_NAMES[$saved_mode]:-desconocido})"
fi

# ── 3. Instalar scripts helper ────────────────────────────────────────────────
mkdir -p "$LIBDIR"

cat > "$LIBDIR/restore.sh" << 'EOF'
#!/usr/bin/env bash
# Ejecutado por asus-gpu-mode-persist.service en ExecStart.
# Si el EC derivó del modo guardado (ej. tras update de BIOS), lo corrige.
SYSFS="/sys/devices/platform/asus-nb-wmi/gpu_mux_mode"
CONFIG="/etc/asus-gpu-mode"
TAG="asus-gpu-mode-persist"

[[ -f "$CONFIG" ]] || { echo "$TAG: $CONFIG no existe, saltando"; exit 0; }
[[ -f "$SYSFS"  ]] || { echo "$TAG: $SYSFS no encontrado, saltando"; exit 0; }

desired=$(cat "$CONFIG")
current=$(cat "$SYSFS")

if [[ "$current" != "$desired" ]]; then
    echo "$desired" > "$SYSFS"
    echo "$TAG: gpu_mux_mode restaurado $current -> $desired"
else
    echo "$TAG: gpu_mux_mode ya es $desired, sin cambios"
fi
EOF

cat > "$LIBDIR/save.sh" << 'EOF'
#!/usr/bin/env bash
# Ejecutado por asus-gpu-mode-persist.service en ExecStop.
# Guarda el modo GPU actual para que el próximo arranque lo restaure.
SYSFS="/sys/devices/platform/asus-nb-wmi/gpu_mux_mode"
CONFIG="/etc/asus-gpu-mode"
TAG="asus-gpu-mode-persist"

[[ -f "$SYSFS" ]] || exit 0

current=$(cat "$SYSFS")
echo "$current" > "$CONFIG"
echo "$TAG: gpu_mux_mode=$current guardado en $CONFIG"
EOF

chmod +x "$LIBDIR/restore.sh" "$LIBDIR/save.sh"
echo "  ✓ Scripts helper instalados en $LIBDIR/"

# ── 4. Crear la unidad systemd ────────────────────────────────────────────────
cat > "$SERVICE_FILE" << UNIT_EOF
[Unit]
Description=Persistir modo GPU (restaurar al arrancar, guardar al apagar)
Documentation=https://github.com/flukejones/asusctl
After=systemd-modules-load.service asusd.service
Before=display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${LIBDIR}/restore.sh
ExecStop=${LIBDIR}/save.sh

[Install]
WantedBy=multi-user.target
UNIT_EOF

echo "  ✓ Servicio creado: $SERVICE_FILE"

# ── 5. Habilitar e iniciar el servicio ────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
echo "  ✓ Servicio habilitado e iniciado"

echo ""
echo "Configuración completada."
echo ""
echo "  Servicio:      ${SERVICE_NAME}.service (habilitado en arranque y apagado)"
echo "  Modo guardado: $saved_mode (${MODE_NAMES[$saved_mode]:-desconocido})"
echo "  Config:        $MODE_CONFIG"
echo ""
echo "  Para cambiar el modo GPU: seleccionalo en ROG Control Center y reiniciá."
echo "  Al apagar, el servicio guarda el nuevo modo automáticamente."
echo ""
echo "  NOTA: Un cambio de modo GPU requiere reiniciar para que el EC"
echo "        lo aplique en el hardware (MUX físico)." 
