# Repository Guidelines

## Project Structure & Module Organization

This repository provides a minimal Linux desktop for Apple Container. Keep changes focused on the small, flat implementation:

- `Containerfile` builds the Ubuntu/XFCE, TigerVNC, and noVNC image.
- `entrypoint.sh` initializes VNC and launches websockify inside the container.
- `acld.sh` implements host-side lifecycle, validation, and mount handling.
- `Makefile` is the public command interface.
- `.github/workflows/ci.yml` defines CI.

There is currently no separate test or asset directory. Add tests alongside a new testing framework only when behavior warrants it.

## Build, Test, and Development Commands

- `make help` lists the supported interface.
- `make check` validates the host architecture, macOS version, and Apple `container` CLI.
- `make build` builds the local `acld:latest` image.
- `make up` builds when needed and starts the desktop; `make down` stops it.
- `make status` reports container state and the noVNC URL.
- `bash -n acld.sh entrypoint.sh` performs a fast shell syntax check.

Run lifecycle commands on Apple silicon macOS 26+; they are not expected to work on Linux hosts.

## Coding Style & Naming Conventions

Shell scripts use Bash, two-space indentation, `set -euo pipefail`, quoted parameter expansions, and `snake_case` functions and local variables. Use uppercase names for exported configuration such as `VNC_PASSWORD`. Prefer small functions, `readonly` constants, Bash arrays for command arguments, and `printf` for messages. Keep Make targets thin: user-facing orchestration belongs in `acld.sh`.

## Testing Guidelines

No automated unit-test framework or coverage threshold exists. Whenever any file is updated, use the `local-qa` skill to run the repository's formatting, linting, and tests. Before submitting, run `bash -n acld.sh entrypoint.sh`. On a supported Mac, also run the relevant lifecycle path (typically `make build`, `make up`, `make status`, and `make down`). CI applies shell linting to `entrypoint.sh`; changes to runtime behavior should include clear manual verification notes in the PR.

## Commit & Pull Request Guidelines

Recent commits use short, imperative, sentence-case subjects, for example `Refine runtime shell scripts` and `Fix container runtime regressions`. Keep each commit focused. PRs should explain the motivation, summarize user-visible changes, list verification commands, and link related issues. Include screenshots only for visible XFCE or noVNC changes; call out configuration, networking, mount, or security implications explicitly.

## Security & Configuration

Never commit credentials or host-specific paths. Keep noVNC bound to `127.0.0.1` by default, and use a non-default VNC password before broader exposure.
