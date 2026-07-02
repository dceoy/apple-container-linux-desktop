# Apple Container Linux Desktop

Run a minimal Linux desktop on macOS using Apple Container, XFCE, TigerVNC, and noVNC.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Apple `container` CLI

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
- thin shell wrappers around `container build` and `container run`
- no Docker Compose compatibility layer
- no Swift wrapper around Apple Containerization APIs

## Usage

Start Apple Container if it is not already running:

```sh
container system start
```

Build the image:

```sh
./scripts/build
```

Run the desktop:

```sh
./scripts/run
```

Open noVNC:

```text
http://localhost:6080/vnc.html
```

Default VNC password:

```text
apple
```

Stop the container from another terminal:

```sh
./scripts/stop
```

## Configuration

Copy the sample environment file and edit it as needed:

```sh
cp .env.example .env
```

Supported variables:

| Variable       | Default                | Description                 |
| -------------- | ---------------------- | --------------------------- |
| `IMAGE`        | `linux-desktop:latest` | Local OCI image name        |
| `NAME`         | `linux-desktop`        | Container name              |
| `HOST_IP`      | `127.0.0.1`            | Host bind address           |
| `PORT`         | `6080`                 | noVNC host port             |
| `CPUS`         | `4`                    | Container CPU allocation    |
| `MEMORY`       | `4G`                   | Container memory allocation |
| `VNC_GEOMETRY` | `1440x900`             | Desktop resolution          |
| `VNC_DEPTH`    | `24`                   | VNC color depth             |
| `VNC_PASSWORD` | `apple`                | VNC password                |

## Shell access

Run an interactive shell in a fresh container:

```sh
./scripts/shell
```

## Security note

The default configuration binds noVNC to `127.0.0.1` on the host. Do not expose the noVNC port to untrusted networks, and set a non-default `VNC_PASSWORD` for real use.

## Scope

This project is a minimal desktop launcher for local development and experimentation. GPU acceleration, Wayland compositors, persistent desktop state, and multi-container orchestration are intentionally out of scope for the initial implementation.
