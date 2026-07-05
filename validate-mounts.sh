#!/usr/bin/env bash
set -euo pipefail

mount_specs=()

if [[ -n "${CLI_VOLUMES:-}" ]]; then
  mount_specs+=("${CLI_VOLUMES}")
fi

if [[ -n "${HOST_MOUNTS_FILE:-}" ]]; then
  if [[ ! -f "${HOST_MOUNTS_FILE}" ]]; then
    printf "ERROR: HOST_MOUNTS_FILE is set to '%s' but that file does not exist.\n" "${HOST_MOUNTS_FILE}" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      '' | \#*) continue ;;
    esac
    mount_specs+=("${line}")
  done <"${HOST_MOUNTS_FILE}"
fi

for spec in "${mount_specs[@]}"; do
  rest="${spec#*:}"
  if [[ "${rest}" == "${spec}" ]]; then
    printf "ERROR: invalid mount '%s' (expected HOST:CONTAINER[:ro|rw]).\n" "${spec}" >&2
    exit 2
  fi

  host="${spec%%:*}"
  case "${rest}" in
    *:ro)
      mode=ro
      target="${rest%:ro}"
      ;;
    *:rw)
      mode=rw
      target="${rest%:rw}"
      ;;
    *)
      mode=rw
      target="${rest}"
      ;;
  esac

  if [[ -z "${host}" || -z "${target}" ]]; then
    printf "ERROR: invalid mount '%s'.\n" "${spec}" >&2
    exit 2
  fi
  if [[ ! -e "${host}" ]]; then
    printf "ERROR: host mount path does not exist: '%s'.\n" "${host}" >&2
    exit 1
  fi
  case "${target}" in
    /*) ;;
    *)
      printf "ERROR: container mount path must be absolute: '%s'.\n" "${target}" >&2
      exit 2
      ;;
  esac
  if [[ "${mode}" == rw ]]; then
    printf "WARNING: mounting '%s' as writable at '%s'. Prefer ':ro' unless write access is required.\n" "${host}" "${target}" >&2
  fi
done
