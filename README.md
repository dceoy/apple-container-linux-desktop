# acld

Run Claude Desktop or a minimal Linux desktop using Apple Container, XFCE, TigerVNC, and noVNC.

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

- two image definitions: `Containerfile.ai` adds Claude Desktop to the minimal
  desktop in `Containerfile.base`; the default `Containerfile` symlink selects
  the AI image for direct `container build .` usage
- one container runtime entrypoint (`entrypoint.sh`)
- one host-side shell script (`acld.sh`) that wraps Apple `container` operations
- one small `Makefile` that loads configuration and dispatches to `acld.sh`
- opt-in host bind mounts only when explicitly configured
- no GUI wrapper, Docker Compose compatibility layer, or Swift application

## Quick start

```sh
make up
```

This safe-to-rerun command:

- loads configuration from `.env` when present, otherwise using Makefile defaults
- selects the `ai` image variant by default
- verifies you're on an Apple silicon Mac, running a supported macOS version, with the `container` CLI installed
- starts the Apple container system if it isn't already running
- builds the selected image only if it doesn't already exist
- starts the selected desktop container detached, unless it's already running
- prints the noVNC URL

Open the printed URL in a browser (default: `http://localhost:6080/vnc.html`) and log in with the VNC password (default: `apple` -- change this, see [Security](#security)).

Run `make up` again at any time: it is safe to re-run and will not create a second container.

## Image variants

List the available variants:

```sh
make variants
```

Use the Claude Desktop image, which is the default:

```sh
make up
make up VARIANT=ai
```

Use the minimal XFCE, TigerVNC, and noVNC image without Claude Desktop:

```sh
make up VARIANT=base
```

`VARIANT` selects the Containerfile, image tag, and container name together:

| Variant | Containerfile        | Image       | Container   |
| ------- | -------------------- | ----------- | ----------- |
| `ai`    | `Containerfile.ai`   | `acld:ai`   | `acld-ai`   |
| `base`  | `Containerfile.base` | `acld:base` | `acld-base` |

All lifecycle commands use the selected variant:

```sh
make build VARIANT=base
make status VARIANT=base
make down VARIANT=base
make clean VARIANT=base
```

The variants can coexist because they use different image and container names. To run both simultaneously, assign a different host port to one of them:

```sh
make up VARIANT=ai
make up VARIANT=base PORT=6081
```

`CONTAINERFILE`, `IMAGE`, and `NAME` remain independently overridable for custom images. The default `Containerfile` symlink is only the fallback for direct `container build .` usage; the Make workflow always passes the selected Containerfile explicitly.

## Make targets

```text
make <target> [VARIABLE=value ...]
```

| Target     | Description                                                                                                             |
| ---------- | ----------------------------------------------------------------------------------------------------------------------- |
| `up`       | Start the selected desktop. Safe to run repeatedly.                                                                    |
| `down`     | Stop the selected desktop container. Safe if it is already stopped.                                                    |
| `status`   | Print whether the selected desktop is running and the noVNC URL. Exits non-zero when not running.                      |
| `shell`    | Open an interactive shell. Uses the selected running container, otherwise starts a temporary one from its image.       |
| `build`    | Build the selected container image.                                                                                    |
| `clean`    | Stop and remove the selected container, then remove its built image.                                                   |
| `variants` | List available `Containerfile.*` image variants.                                                                       |
| `help`     | Show usage.                                                                                                             |

## Configuration

Copy the sample environment file and edit it as needed:

```sh
cp .env.example .env
```

`.env` is loaded automatically by the `Makefile` (and is git-ignored). Any variable not set in `.env` falls back to the default shown below, which matches `.env.example`.

The image runs as the non-root user `agent` with UID and GID `1001`; its home directory is `/home/agent`.

| Variable           | Default                    | Description                                                                                                            |
| ------------------ | -------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `VARIANT`          | `ai`                       | Image variant; selects the derived Containerfile, image tag, and container name                                       |
| `CONTAINERFILE`    | `Containerfile.${VARIANT}` | Container build definition; normally derived from `VARIANT`                                                           |
| `IMAGE`            | `acld:${VARIANT}`          | Local OCI image name; normally derived from `VARIANT`                                                                 |
| `NAME`             | `acld-${VARIANT}`          | Container name; normally derived from `VARIANT`                                                                       |
| `HOST_IP`          | `127.0.0.1`                | Host bind address                                                                                                      |
| `PORT`             | `6080`                     | noVNC host port                                                                                                        |
| `CPUS`             | `4`                        | Container CPU allocation                                                                                               |
| `MEMORY`           | `4G`                       | Container memory allocation                                                                                            |
| `VNC_GEOMETRY`     | `1440x900`                 | Desktop resolution                                                                                                     |
| `VNC_DEPTH`        | `24`                       | VNC color depth                                                                                                        |
| `VNC_PASSWORD`     | `apple`                    | VNC password                                                                                                           |
| `HOST_MOUNTS_FILE` | _(unset)_                  | Path to a file listing host bind mounts. Unset by default: no host paths are mounted. See [Host mounts](#host-mounts). |

Make variables can also be passed inline for one-off overrides:

```sh
make up VARIANT=base PORT=6081 MEMORY=8G
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
make shell VARIANT=base
```

If the selected desktop container is already running, this opens a shell inside it. Otherwise it starts a temporary, disposable container from the selected built image.

## Cleanup

```sh
make down                 # stop the default AI container
make clean                # also remove the default AI image
make clean VARIANT=base   # remove the base container and image
```

`make down` is safe when the selected container is already stopped or absent. `make clean` removes any stale selected container before deleting its image.

## Security

- The default configuration binds noVNC to `HOST_IP=127.0.0.1`, i.e. only reachable from the Mac itself. Do not set `HOST_IP` to `0.0.0.0` (or any non-loopback address) unless the network is trusted -- noVNC and VNC traffic are not encrypted.
- Always set a non-default `VNC_PASSWORD` in `.env` before exposing `PORT` beyond localhost. `make up` warns if the password is still the default.
- Avoid publishing `PORT` through port forwarding, tunnels, or reverse proxies without adding transport encryption (e.g. an SSH tunnel or a TLS-terminating proxy) and a strong `VNC_PASSWORD`.
- Host mounts give the desktop direct access to the mounted host path. Only mount what's needed, prefer `:ro` over `:rw`, and remember that anyone who can reach the desktop (via VNC or `make shell`) can read -- and, for `:rw` mounts, write -- those host files.

## Scope

This project is a minimal desktop launcher for local development and experimentation. GPU acceleration, Wayland compositors, persistent desktop state, and multi-container orchestration are intentionally out of scope.
