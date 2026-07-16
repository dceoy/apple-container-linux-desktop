#!/usr/bin/env bash

set -euo pipefail

readonly AGENT_USER='agent'
readonly AGENT_HOME='/home/agent'
readonly WORKSPACE_DIR='/workspace'

# A newly created named volume is an empty ext4 filesystem owned by
# root:root, so ownership and seeding must happen as root before the
# desktop (or a temporary shell) starts as the non-root agent user.
initialize_agent_dirs() {
  if [[ "$(stat -c '%u:%g' "${AGENT_HOME}")" != "$(id -u "${AGENT_USER}"):$(id -g "${AGENT_USER}")" ]]; then
    chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}"
  fi
  # Seed the persistent home once from the image's default skeleton home. A
  # later start finds it already populated and leaves it untouched.
  if [[ -d /opt/home-skel && -z "$(ls -A "${AGENT_HOME}" 2> /dev/null)" ]]; then
    cp -a /opt/home-skel/. "${AGENT_HOME}/"
  fi
  # A bind-mounted workspace can surface as root-owned inside the guest;
  # chown is best-effort because the mount may not allow it.
  if [[ -d "${WORKSPACE_DIR}" ]] \
    && ! chown "${AGENT_USER}:${AGENT_USER}" "${WORKSPACE_DIR}" 2> /dev/null \
    && ! su -s /bin/bash "${AGENT_USER}" -c "test -w '${WORKSPACE_DIR}'"; then
    printf 'WARNING: %s is not writable by %s; the workspace may be read-only.\n' \
      "${WORKSPACE_DIR}" "${AGENT_USER}" >&2
  fi
}

if [[ "$(id -u)" -eq 0 ]]; then
  initialize_agent_dirs
  exec setpriv --reuid="${AGENT_USER}" --regid="${AGENT_USER}" --init-groups \
    env HOME="${AGENT_HOME}" USER="${AGENT_USER}" LOGNAME="${AGENT_USER}" \
    "${BASH_SOURCE[0]}" "$@"
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
