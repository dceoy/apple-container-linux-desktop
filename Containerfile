FROM ubuntu:26.04

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

LABEL org.opencontainers.image.title="Apple Container Linux Desktop" \
      org.opencontainers.image.description="Minimal XFCE desktop for Apple Container with TigerVNC and noVNC" \
      org.opencontainers.image.source="https://github.com/dceoy/apple-container-linux-desktop" \
      org.opencontainers.image.licenses="MIT"

ARG USERNAME=desktop
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24 \
    VNC_PASSWORD=apple \
    NOVNC_PORT=6080

RUN apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        net-tools \
        novnc \
        procps \
        tigervnc-standalone-server \
        tigervnc-tools \
        tini \
        websockify \
        xfce4 \
        xfce4-terminal; \
    rm -rf /var/lib/apt/lists/*

RUN user_home="/home/${USERNAME}"; \
    if ! getent group "${USER_GID}" >/dev/null; then \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi; \
    existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"; \
    if [ -n "${existing_user}" ]; then \
        if [ "${existing_user}" != "${USERNAME}" ]; then \
            usermod --login "${USERNAME}" --home "${user_home}" --move-home "${existing_user}"; \
        fi; \
        usermod --gid "${USER_GID}" --shell /bin/bash "${USERNAME}"; \
    else \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}"; \
    fi

COPY --chmod=0755 scripts/entrypoint /usr/local/bin/entrypoint

USER ${USERNAME}
WORKDIR /home/${USERNAME}

EXPOSE 6080

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
