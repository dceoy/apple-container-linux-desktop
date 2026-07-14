# acld

Run a minimal Linux desktop on macOS using Apple Container, XFCE, TigerVNC, and noVNC.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Apple `container` CLI ([install instructions](https://github.com/apple/container))
- `make` (included with the macOS command line developer tools)

## Architecture

```text
macOS browser
  -> localhost:6080
  -> noVNC / websockify
  -> TigerVNC X server
  -> XFCE desktop
  -> Apple Container Linux VM
```

This repository intentionally keeps the implementation small:

- one `Containerfile`
- one container runtime entrypoint (`entrypoint.sh`)
- one `Makefile` that wraps Apple `container` operations
- opt-in host bind mounts only when explicitly configured
- no host-side shell wrapper scripts, GUI wrapper, Docker Compose compatibility layer, or Swift application

## Quick start

```sh
make up
```

This safe-to-rerun command:

- loads configuration from `.env` when present, otherwise using Makefile defaults
- verifies you're on an Apple silicon Mac, running a supported macOS version, with the `container` CLI installed
- starts the Apple container system if it isn't already running
- builds the image only if it doesn't already exist
- starts the desktop container detached, unless it's already running
- prints the noVNC URL

Open the printed URL in a browser (default: `http://localhost:6080/vnc.html`) and log in with the VNC password (default: `apple` -- change this, see [Security](#security)).

Run `make up` again at any time: it is safe to re-run and will not create a second container.

## Make targets

```text
make <target> [VARIABLE=value ...]
```

| Target        | Description                                                                                                             |
| ------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `up`          | Start the desktop. Safe to run repeatedly.                                                                              |
| `down`        | Stop the running desktop container. Safe if it is already stopped.                                                      |
| `status`      | Print whether the desktop is running and the noVNC URL. Exits non-zero when not running.                                |
| `shell`       | Open an interactive shell. Uses the running container if there is one, otherwise starts a temporary one from the image. |
| `build`       | Build the container image.                                                                                              |
| `clean`       | Stop and remove the container, then remove the built image.                                                             |
| `help`        | Show usage.                                                                                                             |

## Configuration

Copy the sample environment file and edit it as needed:

```sh
cp .env.example .env
```

`.env` is loaded automatically by the `Makefile` (and is git-ignored). Any variable not set in `.env` falls back to the default shown below, which matches `.env.example`.

The image runs as the non-root user `agent` with UID and GID `1001`; its home directory is `/home/agent`.

| Variable           | Default       | Description                                                                                                            |
| ------------------ | ------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `IMAGE`            | `acld:latest` | Local OCI image name                                                                                                   |
| `NAME`             | `acld`        | Container name                                                                                                         |
| `HOST_IP`          | `127.0.0.1`   | Host bind address                                                                                                      |
| `PORT`             | `6080`        | noVNC host port                                                                                                        |
| `CPUS`             | `4`           | Container CPU allocation                                                                                               |
| `MEMORY`           | `4G`          | Container memory allocation                                                                                            |
| `VNC_GEOMETRY`     | `1440x900`    | Desktop resolution                                                                                                     |
| `VNC_DEPTH`        | `24`          | VNC color depth                                                                                                        |
| `VNC_PASSWORD`     | `apple`       | VNC password                                                                                                           |
| `HOST_MOUNTS_FILE` | _(unset)_     | Path to a file listing host bind mounts. Unset by default: no host paths are mounted. See [Host mounts](#host-mounts). |

Make variables can also be passed inline for one-off overrides:

```sh
PORT=6081 MEMORY=8G make up
```

## Host mounts

No host paths are mounted by default. Mounting is opt-in, two ways:

**Ad hoc, one-off mount** with `CLI_VOLUMES`:

```sh
CLI_VOLUMES="$HOME/Desktop:/home/agent/Desktop" make up
make down && CLI_VOLUMES="$HOME/Downloads:/home/agent/Downloads:ro" make up
```

For multiple persistent mounts, create a local mounts file and point `.env` at it. The expected format is documented in `.env.example`.

```sh
cat > .mounts << EOF
/Users/you/Desktop:/home/agent/Desktop:rw
/Users/you/Downloads:/home/agent/Downloads:ro
EOF
echo 'HOST_MOUNTS_FILE=.mounts' >> .env
```

Notes:

- Blank lines and lines starting with `#` in the mounts file are ignored.
- Mode defaults to `rw` if omitted; use `:ro` for read-only access.
- `make up` validates every mount spec before starting a new container. If the desktop is already running, requested mounts are not applied to the live container; run `make down && make up` to recreate it.
- Mounting a path as `rw` prints a warning -- prefer `:ro` unless the desktop actually needs to write there.
- The container-side path is created automatically by the entrypoint on a best-effort basis (`mkdir -p`). If it lives somewhere the non-root container user can't create (e.g. directly under `/`), pre-create it in a custom image or mount under `/home/agent` instead.

## Shell access

```sh
make shell
```

If the desktop container is already running, this opens a shell inside it. Otherwise it starts a temporary, disposable container from the built image.

## Cleanup

```sh
make down          # stop and remove the auto-removed desktop container
make clean         # also remove the built image
```

`make down` is safe when the container is already stopped or absent. `make clean` removes any stale container before deleting the image.

## Security

- The default configuration binds noVNC to `HOST_IP=127.0.0.1`, i.e. only reachable from the Mac itself. Do not set `HOST_IP` to `0.0.0.0` (or any non-loopback address) unless the network is trusted -- noVNC and VNC traffic are not encrypted.
- Always set a non-default `VNC_PASSWORD` in `.env` before exposing `PORT` beyond localhost. `make up` warns if the password is still the default.
- Avoid publishing `PORT` through port forwarding, tunnels, or reverse proxies without adding transport encryption (e.g. an SSH tunnel or a TLS-terminating proxy) and a strong `VNC_PASSWORD`.
- Host mounts give the desktop direct access to the mounted host path. Only mount what's needed, prefer `:ro` over `:rw`, and remember that anyone who can reach the desktop (via VNC or `make shell`) can read -- and, for `:rw` mounts, write -- those host files.

## Scope

This project is a minimal desktop launcher for local development and experimentation. GPU acceleration, Wayland compositors, persistent desktop state, and multi-container orchestration are intentionally out of scope.
