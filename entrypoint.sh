#!/usr/bin/env bash

set -euo pipefail

# Paths outside what this non-root user can create must already exist.
if [[ -n "${MOUNT_TARGETS:-}" ]]; then
  declare -a mount_targets
  IFS=':' read -r -a mount_targets <<< "${MOUNT_TARGETS}"
  for mount_target in "${mount_targets[@]}"; do
    [[ -z "${mount_target}" ]] && continue
    if ! mkdir -p -- "${mount_target}" 2> /dev/null; then
      printf 'WARNING: could not create mount target %s -- ensure it already exists and is writable\n' "${mount_target}" >&2
    fi
  done
fi

# TigerVNC migrates the legacy ~/.vnc directory to ~/.config/tigervnc on
# first start.  Its migration cannot create ~/.config itself.
install -d -m 700 "${HOME}/.config"
install -d -m 700 "${HOME}/.vnc"

printf '%s\n' "${VNC_PASSWORD}" | vncpasswd -f > "${HOME}/.vnc/passwd"
chmod 600 "${HOME}/.vnc/passwd"

umask 077
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
