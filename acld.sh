#!/usr/bin/env bash

set -euo pipefail

if [[ "${#}" -gt 0 && "${1}" == '--debug' ]]; then
  set -x && shift
fi

readonly IMAGE="${IMAGE:-acld:latest}"
readonly NAME="${NAME:-acld}"
readonly HOST_IP="${HOST_IP:-127.0.0.1}"
readonly PORT="${PORT:-6080}"
readonly CPUS="${CPUS:-4}"
readonly MEMORY="${MEMORY:-4G}"
readonly VNC_GEOMETRY="${VNC_GEOMETRY:-1440x900}"
readonly VNC_DEPTH="${VNC_DEPTH:-24}"
readonly VNC_PASSWORD="${VNC_PASSWORD:-apple}"
readonly HOST_MOUNTS_FILE="${HOST_MOUNTS_FILE:-}"
readonly MIN_MACOS_MAJOR="${MIN_MACOS_MAJOR:-26}"
if [[ "${HOST_IP}" == '0.0.0.0' ]]; then
  NOVNC_HOST='localhost'
else
  NOVNC_HOST="${HOST_IP}"
fi
readonly NOVNC_HOST
readonly NOVNC_URL="http://${NOVNC_HOST}:${PORT}/vnc.html"

# These are built from CLI_VOLUMES and HOST_MOUNTS_FILE immediately before a
# container is started. Keeping them at script scope avoids relying on Bash's
# dynamic local-variable scoping between load_mounts and up.
declare -a volumes=()
mount_count=0
mount_targets=''

container_running() {
  container list --quiet 2> /dev/null | grep -Fx "${NAME}" > /dev/null
}

container_exists() {
  container list --all --quiet 2> /dev/null | grep -Fx "${NAME}" > /dev/null
}

image_exists() {
  container image list --quiet 2> /dev/null | grep -Fx "${IMAGE}" > /dev/null
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

append_mounts() {
  local spec host target mode extra

  while IFS= read -r spec || [[ -n "${spec}" ]]; do
    case "${spec}" in
      ''|\#* )
        continue
        ;;
    esac
    IFS=: read -r host target mode extra <<< "${spec}"
    if [[ -n "${extra:-}" || "${spec}" == *: || -z "${host}" || -z "${target}" ]]; then
      printf "ERROR: invalid mount '%s' (expected HOST:CONTAINER[:ro|rw]).\n" "${spec}" >&2
      return 2
    fi
    mode="${mode:-rw}"
    case "${mode}" in
      ro|rw )
        ;;
      * )
        printf "ERROR: invalid mount mode '%s' in '%s'.\n" "${mode}" "${spec}" >&2
        return 2
        ;;
    esac
    [[ -e "${host}" ]] || { printf "ERROR: host mount path does not exist: '%s'.\n" "${host}" >&2; return 1; }
    [[ "${target}" == /* ]] || { printf "ERROR: container mount path must be absolute: '%s'.\n" "${target}" >&2; return 2; }
    if [[ "${mode}" == rw ]]; then
      printf "WARNING: mounting '%s' as writable at '%s'. Prefer ':ro' unless write access is required.\n" "${host}" "${target}" >&2
    fi
    volumes+=(--volume "${host}:${target}:${mode}")
    ((mount_count += 1))
    mount_targets="${mount_targets:+${mount_targets}:}${target}"
  done
}

load_mounts() {
  volumes=()
  mount_count=0
  mount_targets=''
  if [[ -n "${CLI_VOLUMES:-}" ]]; then
    append_mounts <<< "${CLI_VOLUMES}"
  fi
  if [[ -n "${HOST_MOUNTS_FILE}" ]]; then
    [[ -f "${HOST_MOUNTS_FILE}" ]] || {
      printf "ERROR: HOST_MOUNTS_FILE is set to '%s' but that file does not exist.\n" "${HOST_MOUNTS_FILE}" >&2
      return 1
    }
    append_mounts < "${HOST_MOUNTS_FILE}"
  fi
}

build() {
  check
  container build --platform linux/arm64 --tag "${IMAGE}" .
}

up() {
  local -a container_args

  check
  load_mounts
  if [[ "${VNC_PASSWORD}" == apple ]]; then
    printf 'WARNING: VNC_PASSWORD is still set to the default value.\n' >&2
  fi
  container system status > /dev/null 2>&1 || container system start
  if container_running; then
    printf "Container '%s' is already running.\n" "${NAME}"
    if (( mount_count )); then
      printf "WARNING: requested mounts are not applied to an already-running container; run 'make down && make up' to recreate it.\n" >&2
    fi
    printf 'noVNC:  %s\n' "${NOVNC_URL}"
    return
  fi
  image_exists || build
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
    --env "MOUNT_TARGETS=${mount_targets}"
  )
  container run "${container_args[@]}" "${volumes[@]}" "${IMAGE}" > /dev/null
  printf "Container '%s' started.\n" "${NAME}"
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
  printf 'Image clean complete.\n'
}

shell() {
  check
  container system status > /dev/null 2>&1 || container system start
  if container_running; then
    exec container exec --interactive --tty "${NAME}" /bin/bash
  fi
  if ! image_exists; then
    printf "ERROR: image '%s' not found. Run 'make build' first.\n" "${IMAGE}" >&2
    return 1
  fi
  exec container run --rm --interactive --tty --entrypoint /bin/bash "${IMAGE}"
}

help() {
  cat << EOF
Usage: make <target> [VARIABLE=value ...]

Targets:
  up           Start the desktop; safe to run repeatedly
  down         Stop the running desktop container
  status       Show whether the desktop is running
  shell        Open a shell in the running container, or a temporary one
  build        Build the container image
  clean        Stop and remove the container and built image
  help         Show this help message

Common variables:
  IMAGE, NAME, HOST_IP, PORT, CPUS, MEMORY, VNC_GEOMETRY, VNC_DEPTH, VNC_PASSWORD
  HOST_MOUNTS_FILE=.mounts
  CLI_VOLUMES="HOST:CONTAINER[:ro|rw]"

Configuration is read from .env when present, with Makefile defaults otherwise.
EOF
}

main() {
  local command="${1:-help}"

  if (( $# > 1 )); then
    printf 'ERROR: expected one command, got %s.\n' "$#" >&2
    return 2
  fi

  case "${command}" in
    help|check|build|up|down|status|clean|shell )
      "${command}"
      ;;
    * )
      printf 'ERROR: unknown command: %s\n' "${command}" >&2
      return 2
      ;;
  esac
}

main "$@"
