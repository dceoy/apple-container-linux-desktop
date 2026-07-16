#!/usr/bin/env bash

set -euo pipefail

readonly WORKSPACE_DIR='/workspace'

export HOME='/root'
readonly VNC_CONFIG_DIR="${HOME}/.config/tigervnc"

# Seed the persistent home once from the image's default skeleton home.
# A later start finds it already populated and leaves it untouched.
if [[ -d /opt/home-skel && -z "$(ls -A "${HOME}" 2> /dev/null)" ]]; then
  cp -a /opt/home-skel/. "${HOME}/"
fi

# A bind-mounted workspace can surface as read-only inside the guest.
if [[ -d "${WORKSPACE_DIR}" ]] && [[ ! -w "${WORKSPACE_DIR}" ]]; then
  printf 'WARNING: %s is not writable; the workspace may be read-only.\n' \
    "${WORKSPACE_DIR}" >&2
fi

# With arguments (for example `make shell`), run them instead of the desktop.
if (( ${#} > 0 )); then
  exec "${@}"
fi

: "${VNC_PASSWORD:?VNC_PASSWORD must be set}"

mkdir -p "${VNC_CONFIG_DIR}"
printf '%s\n' "${VNC_PASSWORD}" | vncpasswd -f > "${VNC_CONFIG_DIR}/passwd"
chmod 600 "${VNC_CONFIG_DIR}/passwd"

cat > "${VNC_CONFIG_DIR}/xstartup" << EOF
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x "${VNC_CONFIG_DIR}/xstartup"

vncserver "${DISPLAY}" \
  -geometry "${VNC_GEOMETRY}" \
  -depth "${VNC_DEPTH}" \
  -localhost no

exec websockify \
  --web=/usr/share/novnc \
  "0.0.0.0:${NOVNC_PORT}" \
  localhost:5901
