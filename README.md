# Apple Container Linux Desktop

Run a minimal Linux desktop on macOS using Apple Container, XFCE, TigerVNC, and noVNC.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Apple `container` CLI ([install instructions](https://github.com/apple/container))

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
- one runtime entrypoint
- one POSIX shell CLI (`./linux-desktop`) that wraps `container build` / `container run`
- no GUI wrapper, no Docker Compose compatibility layer, no Swift application

## Quick start

```sh
./linux-desktop up
```

This single, idempotent command:

- loads configuration from `.env` (falling back to the defaults in `.env.example`)
- verifies you're on an Apple silicon Mac, running a supported macOS version, with the `container` CLI installed
- starts the Apple container system if it isn't already running
- builds the image only if it doesn't already exist
- starts the desktop container detached, unless it's already running (in which case it does nothing and just prints how to reach it)
- prints the noVNC URL and the next commands to run

Open the printed URL in a browser (default: `http://localhost:6080/vnc.html`) and log in with the VNC password (default: `apple` -- change this, see [Security](#security)).

Run `./linux-desktop up` again at any time: it is safe to re-run, will not create a second container, and will not rebuild the image unless asked to.

## CLI reference

```text
./linux-desktop <command> [options]
```

| Command   | Description                                                        |
| --------- | ------------------------------------------------------------------- |
| `up`      | Start the desktop. Idempotent; detached by default. `--build`/`--rebuild` forces an image rebuild first. If the desktop is already running, this only rebuilds the image (it never recreates a running container) -- use `restart --build` to rebuild and recreate. |
| `down`    | Stop the running desktop container. Safe to run if it's already stopped or doesn't exist. |
| `restart` | Equivalent to `down` followed by `up`. Accepts `up`'s options.      |
| `status`  | Print whether the desktop is running and, if so, the noVNC URL. Exits non-zero when not running. |
| `shell`   | Open an interactive shell. Uses the running container if there is one, otherwise starts a temporary one from the image. |
| `build`   | Build the container image.                                          |
| `clean`   | Stop and remove the container. `--image`/`--all` also removes the built image (opt-in). |
| `reset`   | `clean` followed by `up`. Accepts `clean`'s and `up`'s options (e.g. `reset --image --build`). |
| `doctor`  | Run diagnostics (architecture, macOS version, `container` CLI, container system status, port availability, VNC password) with remediation guidance. |
| `help`    | Show usage.                                                          |

All commands are idempotent: running `up`, `down`, or `clean` repeatedly is always safe.

If something isn't working, start with:

```sh
./linux-desktop doctor
```

## Configuration

Copy the sample environment file and edit it as needed:

```sh
cp .env.example .env
```

`.env` is loaded automatically by `./linux-desktop` (and is git-ignored). Any variable not set in `.env` falls back to the default shown below, which matches `.env.example`.

| Variable       | Default                | Description                  |
| -------------- | ----------------------- | ----------------------------- |
| `IMAGE`        | `linux-desktop:latest`  | Local OCI image name          |
| `NAME`         | `linux-desktop`         | Container name                |
| `HOST_IP`      | `127.0.0.1`             | Host bind address             |
| `PORT`         | `6080`                  | noVNC host port                |
| `CPUS`         | `4`                     | Container CPU allocation       |
| `MEMORY`       | `4G`                    | Container memory allocation    |
| `VNC_GEOMETRY` | `1440x900`              | Desktop resolution              |
| `VNC_DEPTH`    | `24`                    | VNC color depth                 |
| `VNC_PASSWORD` | `apple`                 | VNC password                    |

## Shell access

```sh
./linux-desktop shell
```

If the desktop container is already running, this opens a shell inside it. Otherwise it starts a temporary, disposable container from the built image.

## Cleanup and reset

```sh
./linux-desktop down           # stop the desktop
./linux-desktop clean          # stop and remove the container
./linux-desktop clean --image  # also remove the built image
./linux-desktop reset          # clean, then start again
```

`down` and `clean` never fail just because the container is already stopped or doesn't exist. Image deletion is opt-in (`--image`/`--all`) so a plain `clean` never discards the built image.

## Security

- The default configuration binds noVNC to `HOST_IP=127.0.0.1`, i.e. only reachable from the Mac itself. Do not set `HOST_IP` to `0.0.0.0` (or any non-loopback address) unless the network is trusted -- noVNC and VNC traffic are not encrypted.
- Always set a non-default `VNC_PASSWORD` in `.env` before exposing `PORT` beyond localhost. `./linux-desktop doctor` warns if the password is still the default.
- Avoid publishing `PORT` through port forwarding, tunnels, or reverse proxies without adding transport encryption (e.g. an SSH tunnel or a TLS-terminating proxy) and a strong `VNC_PASSWORD`.

## Compatibility notes

`scripts/build`, `scripts/run`, `scripts/stop`, and `scripts/shell` still exist and now delegate to `./linux-desktop build`/`up`/`down`/`shell` respectively. The one behavior change: `scripts/run` now starts the desktop **detached** (it returns immediately instead of blocking the terminal in the foreground). Use `./linux-desktop shell`, `./linux-desktop status`, or `./scripts/stop` to interact with or stop it afterwards.

## Scope

This project is a minimal desktop launcher for local development and experimentation. GPU acceleration, Wayland compositors, persistent desktop state, and multi-container orchestration are intentionally out of scope for the initial implementation.
