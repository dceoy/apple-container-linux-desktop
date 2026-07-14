FROM ubuntu:26.04

ARG DEBIAN_FRONTEND='noninteractive'
ARG USER_NAME='agent'
ARG USER_UID='1001'
ARG USER_GID='1001'
ARG VNC_PASSWORD='apple'
ARG VNC_GEOMETRY='1440x900'
ARG VNC_DEPTH='24'
ARG NOVNC_PORT='6080'

LABEL \
  org.opencontainers.image.title="acld" \
  org.opencontainers.image.description="Minimal XFCE desktop for Apple Container with TigerVNC and noVNC" \
  org.opencontainers.image.source="https://github.com/dceoy/acld" \
  org.opencontainers.image.licenses="MIT"

ENV \
  DISPLAY=':1' \
  VNC_PASSWORD="${VNC_PASSWORD}" \
  VNC_GEOMETRY="${VNC_GEOMETRY}" \
  VNC_DEPTH="${VNC_DEPTH}" \
  NOVNC_PORT="${NOVNC_PORT}"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN \
      apt-get -yqq update \
      && apt-get -yqq upgrade \
      && apt-get -yqq install --no-install-recommends --no-install-suggests \
        ca-certificates dbus-x11 novnc procps tigervnc-standalone-server \
        tigervnc-tools tini websockify xfce4 xfce4-terminal \
      && apt-get -yqq autoremove --purge \
      && apt-get -yqq clean \
      && rm -rf /var/lib/apt/lists/*

RUN \
      groupadd --gid "${USER_GID}" "${USER_NAME}" \
      && useradd --uid "${USER_UID}" --gid "${USER_GID}" --shell /bin/bash --create-home "${USER_NAME}"

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint

USER "${USER_NAME}"
WORKDIR "/home/${USER_NAME}"

EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["bash", "-c", "< /dev/tcp/127.0.0.1/${NOVNC_PORT}"]

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
