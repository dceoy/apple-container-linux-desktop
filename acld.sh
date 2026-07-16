#!/usr/bin/env bash

set -euo pipefail

if [[ "${#}" -gt 0 && "${1}" == '--debug' ]]; then
  set -x && shift
fi

readonly VARIANT="${VARIANT:-ai}"
readonly CONTAINERFILE="${CONTAINERFILE:-Containerfile.${VARIANT}}"
readonly IMAGE="${IMAGE:-acld:${VARIANT}}"
readonly REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/dceoy/acld-${VARIANT}:latest}"
readonly NAME="${NAME:-acld-${VARIANT}}"
readonly LEGACY_NAME='acld'
readonly HOST_IP="${HOST_IP:-127.0.0.1}"
readonly PORT="${PORT:-6080}"
readonly CPUS="${CPUS:-4}"
readonly MEMORY="${MEMORY:-4G}"
readonly VNC_GEOMETRY="${VNC_GEOMETRY:-1440x900}"
readonly VNC_DEPTH="${VNC_DEPTH:-24}"
if [[ -n "${VNC_PASSWORD:-}" ]]; then
  readonly VNC_PASSWORD VNC_PASSWORD_GENERATED=0
else
  readonly VNC_PASSWORD="${RANDOM}" VNC_PASSWORD_GENERATED=1
fi
readonly HOME_VOLUME="${HOME_VOLUME:-${NAME}-home}"
readonly CONTAINER_WORKSPACE='/workspace'
readonly WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
readonly MIN_MACOS_MAJOR="${MIN_MACOS_MAJOR:-26}"
if [[ "${HOST_IP}" == '0.0.0.0' ]]; then
  NOVNC_HOST='localhost'
else
  NOVNC_HOST="${HOST_IP}"
fi
readonly NOVNC_HOST
readonly NOVNC_URL="http://${NOVNC_HOST}:${PORT}/vnc.html"

container_running() {
  container list --quiet 2> /dev/null | grep -Fx "${NAME}" > /dev/null
}

container_exists() {
  container list --all --quiet 2> /dev/null | grep -Fx "${NAME}" > /dev/null
}

legacy_container_running() {
  [[ "${VARIANT}" == ai && "${NAME}" == acld-ai && "${HOST_IP}" == 127.0.0.1 && "${PORT}" == 6080 ]] || return 1
  container list --quiet 2> /dev/null | grep -Fx "${LEGACY_NAME}" > /dev/null
}

image_exists() {
  container image list --quiet 2> /dev/null | grep -Fx "${IMAGE}" > /dev/null
}

remote_image_exists() {
  container image list --quiet 2> /dev/null | grep -Fx "${REMOTE_IMAGE}" > /dev/null
}

using_default_containerfile_and_image() {
  [[ "${CONTAINERFILE}" == "Containerfile.${VARIANT}" && "${IMAGE}" == "acld:${VARIANT}" ]]
}

published_variant() {
  [[ "${VARIANT}" == ai || "${VARIANT}" == base ]]
}

check() {
  local arch os version major

  arch="$(uname -m 2> /dev/null || printf unknown)"
  case "${arch}" in
    arm64|aarch64 )
      ;;
    * )
      printf 'ERROR: Apple silicon (arm64) is required; detected %s.\n' "${arch}" >&2
      return 1
      ;;
  esac

  os="$(uname -s 2> /dev/null || printf unknown)"
  if [[ "${os}" != Darwin ]]; then
    printf 'ERROR: macOS is required; detected %s.\n' "${os}" >&2
    return 1
  fi

  if command -v sw_vers > /dev/null 2>&1; then
    version="$(sw_vers -productVersion 2> /dev/null || printf unknown)"
    major="${version%%.*}"
    case "${major}" in
      ''|*[!0-9]* )
        printf 'WARNING: could not determine macOS version; continuing.\n' >&2
        ;;
      * )
        if (( major < MIN_MACOS_MAJOR )); then
          printf 'ERROR: macOS %s or later is required; detected %s.\n' "${MIN_MACOS_MAJOR}" "${version}" >&2
          return 1
        fi
        ;;
    esac
  else
    printf 'WARNING: sw_vers is unavailable; continuing without macOS version validation.\n' >&2
  fi

  command -v container > /dev/null 2>&1 || {
    printf "ERROR: Apple 'container' CLI was not found in PATH.\n" >&2
    return 1
  }
}

variants() {
  local file found=0

  printf 'Available variants:\n'
  for file in Containerfile.*; do
    [[ -f "${file}" ]] || continue
    printf '  %s\n' "${file#Containerfile.}"
    found=1
  done
  if (( ! found )); then
    printf '  (none)\n'
    return 1
  fi
}

validate_containerfile() {
  [[ -f "${CONTAINERFILE}" ]] && return

  printf "ERROR: container definition '%s' for variant '%s' does not exist.\n" "${CONTAINERFILE}" "${VARIANT}" >&2
  variants >&2 || true
  return 2
}

validate_workspace_dir() {
  [[ -d "${WORKSPACE_DIR}" ]] || {
    printf "ERROR: WORKSPACE_DIR does not exist or is not a directory: '%s'.\n" "${WORKSPACE_DIR}" >&2
    return 2
  }
}

build() {
  validate_containerfile
  check
  container build --platform linux/arm64 --file "${CONTAINERFILE}" --tag "${IMAGE}" .
}

pull() {
  check
  container system status > /dev/null 2>&1 || container system start
  printf "Pulling image '%s'...\n" "${REMOTE_IMAGE}"
  container image pull --platform linux/arm64 "${REMOTE_IMAGE}"
  if [[ "${REMOTE_IMAGE}" != "${IMAGE}" ]]; then
    container image tag "${REMOTE_IMAGE}" "${IMAGE}"
  fi
}

up() {
  local -a container_args

  check
  validate_workspace_dir
  container system status > /dev/null 2>&1 || container system start
  if container_running; then
    printf "Container '%s' is already running.\n" "${NAME}"
    printf 'noVNC:  %s\n' "${NOVNC_URL}"
    return
  fi
  if legacy_container_running; then
    printf "ERROR: legacy container '%s' is still running on the default noVNC endpoint.\n" "${LEGACY_NAME}" >&2
    printf "Stop it with 'make down NAME=%s', then run 'make up' again.\n" "${LEGACY_NAME}" >&2
    return 1
  fi
  if ! image_exists; then
    if using_default_containerfile_and_image && published_variant; then
      pull
    else
      build
    fi
  fi
  if container_exists; then
    printf "Removing stale container '%s'...\n" "${NAME}"
    container delete "${NAME}" > /dev/null
  fi
  printf "Starting container '%s'...\n" "${NAME}"
  container_args=(
    --detach --rm
    --name "${NAME}"
    --cpus "${CPUS}"
    --memory "${MEMORY}"
    --publish "${HOST_IP}:${PORT}:6080"
    --env "VNC_GEOMETRY=${VNC_GEOMETRY}"
    --env "VNC_DEPTH=${VNC_DEPTH}"
    --env "VNC_PASSWORD=${VNC_PASSWORD}"
    --volume "${HOME_VOLUME}:/root"
    --volume "${WORKSPACE_DIR}:${CONTAINER_WORKSPACE}"
  )
  container run "${container_args[@]}" "${IMAGE}" > /dev/null
  printf "Container '%s' started.\n" "${NAME}"
  if (( VNC_PASSWORD_GENERATED )); then
    printf 'VNC password (randomly generated): %s\n' "${VNC_PASSWORD}"
  fi
  printf 'noVNC:  %s\n' "${NOVNC_URL}"
}

down() {
  if container_running; then
    printf "Stopping container '%s'...\n" "${NAME}"
    container stop "${NAME}" > /dev/null 2>&1 || true
  else
    printf "Container '%s' is not running.\n" "${NAME}"
  fi
}

status() {
  printf 'Container: %s\n' "${NAME}"
  if container_running; then
    printf 'Status:    running\nnoVNC:     %s\n' "${NOVNC_URL}"
  elif container_exists; then
    printf 'Status:    stopped (stale container present)\n'
    return 1
  else
    printf 'Status:    not running\n'
    return 1
  fi
}

clean() {
  if container_running; then
    container stop "${NAME}" > /dev/null
  fi
  if container_exists; then
    container delete "${NAME}" > /dev/null
  fi
  if image_exists; then
    container image delete "${IMAGE}" > /dev/null
  fi
  if [[ "${REMOTE_IMAGE}" != "${IMAGE}" ]] && remote_image_exists; then
    container image delete "${REMOTE_IMAGE}" > /dev/null
  fi
  printf 'Image clean complete.\n'
}

shell() {
  check
  validate_workspace_dir
  container system status > /dev/null 2>&1 || container system start
  if container_running; then
    exec container exec --interactive --tty "${NAME}" /usr/local/bin/entrypoint /bin/bash
  fi
  if ! image_exists; then
    printf "ERROR: image '%s' not found. Run 'make pull' or 'make build' first.\n" "${IMAGE}" >&2
    return 1
  fi
  exec container run --rm --interactive --tty \
    --volume "${HOME_VOLUME}:/root" \
    --volume "${WORKSPACE_DIR}:${CONTAINER_WORKSPACE}" \
    "${IMAGE}" /bin/bash --login
}

help() {
  cat << EOF
Usage: make <target> [VARIABLE=value ...]

Targets:
  up           Start the selected desktop; safe to run repeatedly
  down         Stop the selected desktop container
  status       Show whether the selected desktop is running
  shell        Open a shell in the selected container, or a temporary one
  pull         Pull the selected image from the registry and tag it locally
  build        Build the selected container image locally
  clean        Stop and remove the selected container and its images
  variants     List available image variants
  help         Show this help message

Common variables:
  VARIANT=ai|base
  CONTAINERFILE=Containerfile.\${VARIANT}
  IMAGE=acld:\${VARIANT}
  REMOTE_IMAGE=ghcr.io/dceoy/acld-\${VARIANT}:latest
  NAME=acld-\${VARIANT}
  HOST_IP, PORT, CPUS, MEMORY, VNC_GEOMETRY, VNC_DEPTH, VNC_PASSWORD
  HOME_VOLUME=\${NAME}-home
  WORKSPACE_DIR=<current directory>

Configuration uses Makefile defaults unless variables are overridden.
EOF
}

main() {
  local command="${1:-help}"

  if (( ${#} > 1 )); then
    printf 'ERROR: expected one command, got %s.\n' "${#}" >&2
    return 2
  fi

  case "${command}" in
    help|check|variants|pull|build|up|down|status|clean|shell )
      "${command}"
      ;;
    * )
      printf 'ERROR: unknown command: %s\n' "${command}" >&2
      return 2
      ;;
  esac
}

main "${@}"
