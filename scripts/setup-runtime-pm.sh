#!/usr/bin/env bash
# setup-runtime-pm.sh
# Habilita el runtime power management para dispositivos PCI, NVMe y USB.
#
# Por defecto, muchos dispositivos PCIe permanecen en estado "active" aunque
# estén inactivos, consumiendo varios vatios innecesariamente. Este script
# instala un servicio que los pone en suspensión automática al arranque.
#
# Qué hace:
#   - PCI: activa "auto" power/control en todos los dispositivos PCIe
#   - NVMe: activa runtime PM del SSD
#   - USB: activa autosuspend excepto en dispositivos HID (teclado, ratón)
#
# Requisitos: systemd
#
# Uso: sudo bash setup-runtime-pm.sh

set -euo pipefail

SCRIPT_PATH="/usr/local/bin/pci-runtime-pm"
SERVICE_PATH="/etc/systemd/system/powertop-autotune.service"

# ── 1. Script pci-runtime-pm ──────────────────────────────────────────────────
cat > "$SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# pci-runtime-pm: Enable PCI/USB runtime power management.
# Called at boot by powertop-autotune.service.

# PCI devices: enable runtime autosuspend
for dev in /sys/bus/pci/devices/*/power/control; do
    echo auto > "$dev" 2>/dev/null
done

# USB: enable autosuspend, but protect devices whose interfaces are bound to:
#   - usbhid        : keyboards, mice, touchpads
#   - hid-playstation: DualSense / DualShock controllers
#   - hid-generic   : other HID gamepads
#   - snd-usb-audio : USB audio (DualSense headset jack, USB headsets)
#
# Interface nodes (e.g. 7-1:1.0) are SIBLINGS of the device node (7-1) under
# /sys/bus/usb/devices/, so we search for "${dev_name}:*" among siblings.
for dev_path in /sys/bus/usb/devices/*/; do
    dev_name=$(basename "$dev_path")
    [[ "$dev_name" == *:* ]] && continue  # skip interface nodes

    protected=0
    for iface_path in /sys/bus/usb/devices/"${dev_name}":*/; do
        [[ -d "$iface_path" ]] || continue
        iface_driver=$(basename "$(readlink -f "${iface_path}driver" 2>/dev/null)" 2>/dev/null)
        case "$iface_driver" in
            usbhid|hid-playstation|hid-generic|snd-usb-audio)
                protected=1
                break
                ;;
        esac
    done

    if [[ "$protected" -eq 1 ]]; then
        echo on   > "${dev_path}power/control" 2>/dev/null
    else
        echo auto > "${dev_path}power/control" 2>/dev/null
    fi
done
EOF
chmod +x "$SCRIPT_PATH"
echo "  ✓ $SCRIPT_PATH"

# ── 2. Systemd service ────────────────────────────────────────────────────────
cat > "$SERVICE_PATH" << 'EOF'
[Unit]
Description=PCI/USB Runtime Power Management
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pci-runtime-pm

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now powertop-autotune.service
echo "  ✓ powertop-autotune.service habilitado y activo"

echo ""
echo "Configuración completada."
echo ""
echo "  Dispositivos PCI/NVMe/USB se suspenderán automáticamente cuando estén inactivos."
echo "  Ahorro típico: ~8–10 W en batería."
