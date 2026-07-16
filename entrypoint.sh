#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_HOME='/root'
readonly WORKSPACE_DIR='/workspace'

export HOME="${ROOT_HOME}"

# Seed the persistent home once from the image's default skeleton home. A
# later start finds it already populated and leaves it untouched.
if [[ -d /opt/home-skel && -z "$(ls -A "${ROOT_HOME}" 2> /dev/null)" ]]; then
  cp -a /opt/home-skel/. "${ROOT_HOME}/"
fi

# A bind-mounted workspace can surface as read-only inside the guest.
if [[ -d "${WORKSPACE_DIR}" ]] && [[ ! -w "${WORKSPACE_DIR}" ]]; then
  printf 'WARNING: %s is not writable; the workspace may be read-only.\n' \
    "${WORKSPACE_DIR}" >&2
fi

# With arguments (for example `make shell`), run them instead of the desktop.
if (( $# > 0 )); then
  exec "$@"
fi

: "${VNC_PASSWORD:?VNC_PASSWORD must be set}"

# TigerVNC migrates the legacy ~/.vnc directory to ~/.config/tigervnc on
# first start.  Its migration cannot create ~/.config itself.
install -d -m 700 "${HOME}/.config"
install -d -m 700 "${HOME}/.vnc"

printf '%s\n' "${VNC_PASSWORD}" | vncpasswd -f > "${HOME}/.vnc/passwd"
chmod 600 "${HOME}/.vnc/passwd"

cat > "${HOME}/.vnc/xstartup" << EOF
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chmod +x "${HOME}/.vnc/xstartup"

vncserver "${DISPLAY}" \
  -geometry "${VNC_GEOMETRY}" \
  -depth "${VNC_DEPTH}" \
  -localhost no

exec websockify \
  --web=/usr/share/novnc \
  "0.0.0.0:${NOVNC_PORT}" \
  localhost:5901
