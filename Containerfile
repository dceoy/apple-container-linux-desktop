FROM ubuntu:24.04

ARG USERNAME=desktop
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24 \
    VNC_PASSWORD=apple \
    NOVNC_PORT=6080

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        net-tools \
        novnc \
        procps \
        tigervnc-standalone-server \
        tini \
        websockify \
        xfce4 \
        xfce4-terminal \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 scripts/entrypoint /usr/local/bin/entrypoint

USER ${USERNAME}
WORKDIR /home/${USERNAME}

EXPOSE 6080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
