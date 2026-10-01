#!/usr/bin/env bash
# setup-bluetooth-audio-fix.sh
# Corrige dos problemas de audio Bluetooth del ASUS ROG Zephyrus G14 GA403UV
# (adaptador MediaTek MT7922):
#
#   1. Ruido blanco al reproducir por auriculares Bluetooth.
#      El firmware del MT7922 falla con el códec AAC: el audio llega como
#      ruido/estática. Se deshabilita AAC y se deja SBC-XQ como códec
#      preferido (SBC de respaldo), conservando los códecs de manos libres
#      (mSBC/CVSD) para el micrófono.
#
#   2. El audio de algunas apps (p. ej. Chromium) queda pegado a los parlantes
#      internos aunque el dispositivo predeterminado sea el auricular.
#      WirePlumber guarda el destino ("target") por aplicación y lo restaura
#      en cada sesión. Se desactiva la restauración de destino para las
#      salidas de audio, de modo que todas sigan el sink predeterminado.
#
# Instala en el usuario que invocó sudo:
#   ~/.config/wireplumber/wireplumber.conf.d/bluetooth-codecs.conf
#   ~/.config/wireplumber/wireplumber.conf.d/stream-no-target-restore.conf
#
# Uso: sudo bash setup-bluetooth-audio-fix.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo $0)" >&2
    exit 1
fi

target_user="${SUDO_USER:-}"
target_home="${HOME}"
if [[ -n "$target_user" ]]; then
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
fi

echo "[INFO] Aplicando arreglos de audio Bluetooth (MT7922 + destinos de apps)..."

wp_conf_dir="$target_home/.config/wireplumber/wireplumber.conf.d"
install -d -m 755 "$wp_conf_dir"

cat >"$wp_conf_dir/bluetooth-codecs.conf" <<'EOF'
## Deshabilita el códec AAC para A2DP.
## El adaptador MediaTek MT7922 tiene un bug de firmware que convierte el audio
## AAC en ruido blanco. Se usa SBC-XQ, con SBC de respaldo. Se mantienen los
## códecs de manos libres (mSBC/CVSD) para el micrófono.

monitor.bluez.properties = {
  bluez5.codecs = [ sbc_xq sbc msbc cvsd ]
  bluez5.enable-msbc = true
}
EOF

cat >"$wp_conf_dir/stream-no-target-restore.conf" <<'EOF'
## No recordar ni restaurar el destino por aplicación en las salidas de audio.
## Un destino viejo (p. ej. Chromium fijado a los parlantes internos) hace que
## la app siga sonando en el dispositivo equivocado en lugar de seguir el sink
## predeterminado actual.

stream.rules = [
  {
    matches = [
      { media.class = "Stream/Output/Audio" }
    ]
    actions = {
      update-props = {
        state.restore-target = false
      }
    }
  }
]
EOF

if [[ -n "$target_user" ]]; then
    chown "$target_user:$target_user" \
        "$wp_conf_dir/bluetooth-codecs.conf" \
        "$wp_conf_dir/stream-no-target-restore.conf"
fi

echo "[INFO] Archivos creados:"
echo "       $wp_conf_dir/bluetooth-codecs.conf"
echo "       $wp_conf_dir/stream-no-target-restore.conf"

if [[ -n "$target_user" ]]; then
    target_uid="$(id -u "$target_user")"
    if [[ -S "/run/user/$target_uid/bus" ]]; then
        echo "[INFO] Reiniciando WirePlumber para aplicar los cambios..."
        sudo -u "$target_user" \
            XDG_RUNTIME_DIR="/run/user/$target_uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$target_uid/bus" \
            systemctl --user restart wireplumber || true
        echo "[WARN] Si el auricular ya estaba conectado, desconectalo y volvé a"
        echo "       conectarlo para que reaparezca la tarjeta de audio."
    else
        echo "[WARN] No se encontró el bus de sesión; reinicia sesión para aplicar WirePlumber."
    fi
else
    echo "[WARN] Ejecutado sin SUDO_USER; reinicia sesión para aplicar WirePlumber."
fi

echo ""
echo "Verificación (como usuario):"
echo "  pactl list sinks | grep api.bluez5.codec   # debe decir \"sbc_xq\""
echo "  pactl get-default-sink                      # debe ser bluez_output.*"
