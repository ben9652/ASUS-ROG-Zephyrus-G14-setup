#!/usr/bin/env bash
# setup-dualsense-bluetooth-stability.sh
# Mejora estabilidad del DualSense por Bluetooth en MT7921e/MT7922.

set -euo pipefail

echo "[INFO] Aplicando ajustes de estabilidad Bluetooth para DualSense..."

target_user="${SUDO_USER:-}"
target_home="${HOME}"
if [[ -n "$target_user" ]]; then
	target_home="$(getent passwd "$target_user" | cut -d: -f6)"
fi

install -d -m 755 /etc/modprobe.d

cat >/etc/modprobe.d/bluetooth-dualsense.conf <<'EOF'
# Evita desconexiones HID de DualSense por EAGAIN en BlueZ (hidp_send_message)
options bluetooth disable_ertm=Y
EOF

cat >/etc/modprobe.d/mt7921e-stability.conf <<'EOF'
# Mitiga cortes intermitentes en combo Wi-Fi/Bluetooth Mediatek
options mt7921e disable_aspm=Y
EOF

wp_conf_dir="$target_home/.config/wireplumber/wireplumber.conf.d"
install -d -m 755 "$wp_conf_dir"

cat >"$wp_conf_dir/dualsense-audio-block.conf" <<'EOF'
# Desactiva SOLO nodos de audio del DualSense Bluetooth para evitar cortes HID.
# Mantiene input del gamepad (vibracion/luces/controles).
monitor.bluez.rules = [
	{
		matches = [
			{
				media.class = "Audio/Sink"
				device.product.id = "0x0ce6"
			},
			{
				media.class = "Audio/Source"
				device.product.id = "0x0ce6"
			},
			{
				node.name = "~bluez_output\\..*"
				node.nick = "~.*DualSense.*"
			},
			{
				node.name = "~bluez_input\\..*"
				node.nick = "~.*DualSense.*"
			}
		]
		actions = {
			update-props = {
				node.disabled = true
			}
		}
	}
]
EOF

if [[ -n "$target_user" ]]; then
		chown "$target_user:$target_user" "$wp_conf_dir/dualsense-audio-block.conf"
fi

echo "[INFO] Archivos creados:"
echo "       /etc/modprobe.d/bluetooth-dualsense.conf"
echo "       /etc/modprobe.d/mt7921e-stability.conf"
echo "       $wp_conf_dir/dualsense-audio-block.conf"

if [[ -n "$target_user" ]]; then
		target_uid="$(id -u "$target_user")"
		if [[ -S "/run/user/$target_uid/bus" ]]; then
				echo "[INFO] Reiniciando WirePlumber para aplicar bloqueo de audio..."
				sudo -u "$target_user" \
						XDG_RUNTIME_DIR="/run/user/$target_uid" \
						DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$target_uid/bus" \
						systemctl --user restart wireplumber || true
		else
				echo "[WARN] No se encontro bus de sesion de usuario; reinicia sesion para aplicar WirePlumber."
		fi
else
		echo "[WARN] Ejecutado sin SUDO_USER; reinicia sesion para aplicar WirePlumber."
fi

echo "[WARN] Se requiere reiniciar para aplicar ambos parámetros del kernel."