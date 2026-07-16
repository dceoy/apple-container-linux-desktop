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
  desktop in `Containerfile.base`
- one container runtime entrypoint (`entrypoint.sh`)
- one host-side shell script (`acld.sh`) that wraps Apple `container` operations
- one small `Makefile` that loads configuration and dispatches to `acld.sh`
- exactly one host bind mount (the workspace) plus one persistent named volume (the home directory)
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
- pulls the selected image from GitHub Container Registry only if it doesn't already exist locally, for the published `ai`/`base` variants with default `CONTAINERFILE`/`IMAGE`; otherwise it builds locally
- starts the selected desktop container detached, unless it's already running
- bind-mounts the current directory (or `WORKSPACE_DIR`) read-write at `/workspace`, and attaches a persistent named volume at `/root`
- prints the noVNC URL

Open the printed URL in a browser (default: `http://localhost:6080/vnc.html`) and log in with the VNC password. When `VNC_PASSWORD` is left empty, `make up` generates a random password and prints it once at startup (see [Security](#security)).

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

When upgrading from a version that used the container name `acld`, stop that legacy container once before starting the default `acld-ai` container:

```sh
make down NAME=acld
make up
```

The default `make up` detects a running legacy container on the old default noVNC endpoint and prints this migration command instead of attempting to start a conflicting container.

`CONTAINERFILE`, `IMAGE`, `REMOTE_IMAGE`, and `NAME` remain independently overridable for custom images. `make up` only pulls from GitHub Container Registry for the published `ai`/`base` variants with default `CONTAINERFILE`/`IMAGE`; any other variant (including a locally added `Containerfile.foo`), or an overridden `CONTAINERFILE`/`IMAGE`, is built locally instead, since no matching image is published for it. The Make workflow always passes the selected Containerfile explicitly; direct `container build` commands must also specify `--file`.

## Make targets

```text
make <target> [VARIABLE=value ...]
```

| Target     | Description                                                                                                      |
| ---------- | ---------------------------------------------------------------------------------------------------------------- |
| `up`       | Start the selected desktop. Safe to run repeatedly.                                                              |
| `down`     | Stop the selected desktop container. Safe if it is already stopped.                                              |
| `status`   | Print whether the selected desktop is running and the noVNC URL. Exits non-zero when not running.                |
| `shell`    | Open an interactive shell. Uses the selected running container, otherwise starts a temporary one from its image. |
| `pull`     | Pull the selected image from GitHub Container Registry and tag it as the local image.                            |
| `build`    | Build the selected container image locally.                                                                      |
| `clean`    | Stop and remove the selected container, then remove its local and pulled images.                                 |
| `variants` | List available `Containerfile.*` image variants.                                                                 |
| `help`     | Show usage.                                                                                                      |

## Configuration

Copy the sample environment file and edit it as needed:

```sh
cp .env.example .env
```

`.env` is loaded automatically by the `Makefile` (and is git-ignored). Any variable not set in `.env` falls back to the default shown below, which matches `.env.example`.

Everything in the container runs as `root`; the entrypoint seeds the persistent home volume at `/root` on first start, and the default working directory is `/workspace`.

| Variable        | Default                                | Description                                                                                                                  |
| --------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `VARIANT`       | `ai`                                   | Image variant; selects the derived Containerfile, image tag, and container name                                              |
| `CONTAINERFILE` | `Containerfile.${VARIANT}`             | Container build definition; normally derived from `VARIANT`                                                                  |
| `IMAGE`         | `acld:${VARIANT}`                      | Local OCI image name; normally derived from `VARIANT`                                                                        |
| `REMOTE_IMAGE`  | `ghcr.io/dceoy/acld-${VARIANT}:latest` | Registry image reference used by `make pull`; normally derived from `VARIANT`                                                |
| `NAME`          | `acld-${VARIANT}`                      | Container name; normally derived from `VARIANT`                                                                              |
| `HOST_IP`       | `127.0.0.1`                            | Host bind address                                                                                                            |
| `PORT`          | `6080`                                 | noVNC host port                                                                                                              |
| `CPUS`          | `4`                                    | Container CPU allocation                                                                                                     |
| `MEMORY`        | `4G`                                   | Container memory allocation                                                                                                  |
| `VNC_GEOMETRY`  | `1440x900`                             | Desktop resolution                                                                                                           |
| `VNC_DEPTH`     | `24`                                   | VNC color depth                                                                                                              |
| `VNC_PASSWORD`  | (randomly generated when empty)        | VNC password                                                                                                                 |
| `WORKSPACE_DIR` | current directory                      | Host directory bind-mounted read-write at `/workspace`. See [Workspace and persistent home](#workspace-and-persistent-home). |
| `HOME_VOLUME`   | `acld-${VARIANT}-home`                 | Named volume backing the persistent `/root` home. See [Workspace and persistent home](#workspace-and-persistent-home).       |

Make variables can also be passed inline for one-off overrides:

```sh
make up VARIANT=base PORT=6081 MEMORY=8G
```

## Workspace and persistent home

Every `make up` attaches exactly two mounts -- there is no support for mounting additional host paths:

- **Workspace**: the host directory `make up` is run from is bind-mounted read-write at `/workspace`, which is also the container's default working directory. Override the host side with `WORKSPACE_DIR`:

  ```sh
  WORKSPACE_DIR=~/projects/demo make up
  ```

- **Home**: `/root` is backed by a named Apple Container volume (`HOME_VOLUME`, default `acld-${VARIANT}-home`) so desktop settings, Claude Desktop configuration, and anything else written under the home directory survive `make down` / `make up` cycles. The volume is created automatically and seeded once from the image's default home skeleton the first time it's used; later starts leave its contents untouched.

Notes:

- `WORKSPACE_DIR` must exist and be a directory; `make up` and `make shell` validate it first.
- The workspace mount is always read-write -- only run `make up` from (or point `WORKSPACE_DIR` at) a directory whose contents you're comfortable with the desktop reading and modifying.
- Both mounts are fixed at container creation; changing `WORKSPACE_DIR` or `HOME_VOLUME` only takes effect on the next `make down && make up`, not on an already-running container.
- To reset the persistent home directory, stop the container and delete its volume:

  ```sh
  make down
  container volume rm acld-ai-home
  ```

## Shell access

```sh
make shell
make shell VARIANT=base
```

`make shell` mounts the same workspace directory and persistent home volume as `make up`.

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
- Set an explicit `VNC_PASSWORD` in `.env` before exposing `PORT` beyond localhost. When it is left empty, `make up` generates a random password and prints it once at startup.
- Avoid publishing `PORT` through port forwarding, tunnels, or reverse proxies without adding transport encryption (e.g. an SSH tunnel or a TLS-terminating proxy) and a strong `VNC_PASSWORD`.
- The workspace mount gives the desktop direct, read-write access to the host directory `make up` runs from (or `WORKSPACE_DIR`). Anyone who can reach the desktop (via VNC or `make shell`) can read and write those host files, so only run it from -- or point `WORKSPACE_DIR` at -- a directory you're comfortable exposing.
- The persistent home volume (`HOME_VOLUME`) retains its contents across restarts. Treat it like any other local state: it isn't encrypted at rest, and `make clean` does not remove it (see [Workspace and persistent home](#workspace-and-persistent-home) to reset it).

## Scope

This project is a minimal desktop launcher for local development and experimentation. GPU acceleration, Wayland compositors, and multi-container orchestration are intentionally out of scope. The home directory persists across restarts (see [Workspace and persistent home](#workspace-and-persistent-home)); no other desktop state does.
