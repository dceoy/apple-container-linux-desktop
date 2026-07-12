.DEFAULT_GOAL := help
SHELL := /bin/bash

-include .env

IMAGE ?= acld:latest
NAME ?= acld
HOST_IP ?= 127.0.0.1
PORT ?= 6080
CPUS ?= 4
MEMORY ?= 4G
VNC_GEOMETRY ?= 1440x900
VNC_DEPTH ?= 24
VNC_PASSWORD ?= apple
HOST_MOUNTS_FILE ?=
MIN_MACOS_MAJOR ?= 26

export IMAGE NAME HOST_IP PORT CPUS MEMORY VNC_GEOMETRY VNC_DEPTH VNC_PASSWORD HOST_MOUNTS_FILE MIN_MACOS_MAJOR
export CLI_VOLUMES

CONTAINER_RUNNING = container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null
CONTAINER_EXISTS = container list --all --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null
IMAGE_EXISTS = container image list --quiet 2>/dev/null | grep -Fx "$$IMAGE" >/dev/null
NOVNC_URL = http://$(if $(filter 0.0.0.0,$(HOST_IP)),localhost,$(HOST_IP)):$(PORT)/vnc.html

define MOUNT_HELPERS
append_mounts() { \
	local spec host target mode extra; \
	while IFS= read -r spec || [[ -n "$$spec" ]]; do \
		case "$$spec" in ''|\#*) continue ;; esac; \
		IFS=: read -r host target mode extra <<<"$$spec"; \
		if [[ -n "$${extra:-}" || "$$spec" == *: || -z "$$host" || -z "$$target" ]]; then echo "ERROR: invalid mount '$$spec' (expected HOST:CONTAINER[:ro|rw])." >&2; return 2; fi; \
		mode="$${mode:-rw}"; \
		case "$$mode" in ro|rw) : ;; *) echo "ERROR: invalid mount mode '$$mode' in '$$spec'." >&2; return 2 ;; esac; \
		[[ -e "$$host" ]] || { echo "ERROR: host mount path does not exist: '$$host'." >&2; return 1; }; \
		[[ "$$target" == /* ]] || { echo "ERROR: container mount path must be absolute: '$$target'." >&2; return 2; }; \
		if [[ "$$mode" == rw ]]; then echo "WARNING: mounting '$$host' as writable at '$$target'. Prefer ':ro' unless write access is required." >&2; fi; \
		volumes+=(--volume "$$host:$$target:$$mode"); \
		mount_targets="$${mount_targets:+$$mount_targets:}$$target"; \
	done; \
}; \
load_mounts() { \
	volumes=(); mount_targets=; \
	if [[ -n "$${CLI_VOLUMES:-}" ]]; then append_mounts <<<"$$CLI_VOLUMES" || return; fi; \
	if [[ -n "$${HOST_MOUNTS_FILE:-}" ]]; then \
		[[ -f "$$HOST_MOUNTS_FILE" ]] || { echo "ERROR: HOST_MOUNTS_FILE is set to '$$HOST_MOUNTS_FILE' but that file does not exist." >&2; return 1; }; \
		append_mounts <"$$HOST_MOUNTS_FILE" || return; \
	fi; \
};
endef

.PHONY: help check doctor build up down restart status clean clean-image shell

help:
	@printf '%s\n' \
		'Usage: make <target> [VARIABLE=value ...]' \
		'' \
		'Targets:' \
		'  up           Start the desktop; safe to run repeatedly' \
		'  down         Stop the running desktop container' \
		'  restart      Stop and start the desktop' \
		'  status       Show whether the desktop is running' \
		'  shell        Open a shell in the running container, or a temporary one' \
		'  build        Build the container image' \
		'  clean        Stop and remove the container' \
		'  clean-image  Stop and remove the container and built image' \
		'  doctor       Run basic diagnostics' \
		'  help         Show this help message' \
		'' \
		'Common variables:' \
		'  IMAGE, NAME, HOST_IP, PORT, CPUS, MEMORY, VNC_GEOMETRY, VNC_DEPTH, VNC_PASSWORD' \
		'  HOST_MOUNTS_FILE=.mounts' \
		'  CLI_VOLUMES="HOST:CONTAINER[:ro|rw]"' \
		'' \
		'Configuration is read from .env when present, with Makefile defaults otherwise.'

check:
	@set -euo pipefail; \
	arch=$$(uname -m 2>/dev/null || printf unknown); \
	case "$$arch" in arm64|aarch64) : ;; *) echo "ERROR: Apple silicon (arm64) is required; detected $$arch." >&2; exit 1 ;; esac; \
	os=$$(uname -s 2>/dev/null || printf unknown); \
	[[ "$$os" == Darwin ]] || { echo "ERROR: macOS is required; detected $$os." >&2; exit 1; }; \
	if command -v sw_vers >/dev/null 2>&1; then \
		version=$$(sw_vers -productVersion 2>/dev/null || printf unknown); major="$${version%%.*}"; \
		case "$$major" in ''|*[!0-9]*) echo "WARNING: could not determine macOS version; continuing." >&2 ;; \
		*) (( major >= MIN_MACOS_MAJOR )) || { echo "ERROR: macOS $$MIN_MACOS_MAJOR or later is required; detected $$version." >&2; exit 1; } ;; esac; \
	else echo "WARNING: sw_vers is unavailable; continuing without macOS version validation." >&2; fi; \
	command -v container >/dev/null 2>&1 || { echo "ERROR: Apple 'container' CLI was not found in PATH." >&2; exit 1; }

doctor:
	@set -euo pipefail; \
	echo "== acld doctor =="; \
	if $(MAKE) --no-print-directory check; then echo "[ OK ] Platform prerequisites"; else echo "[FAIL] Platform prerequisites"; exit 1; fi; \
	if container system status >/dev/null 2>&1; then echo "[ OK ] Apple container system: running"; else echo "[WARN] Apple container system: not running; 'up' will start it"; fi; \
	if [[ "$$VNC_PASSWORD" == apple ]]; then echo "[WARN] VNC_PASSWORD: still set to the default value"; else echo "[ OK ] VNC_PASSWORD: overridden from the default"; fi

build: check
	@container build --platform linux/arm64 --tag "$$IMAGE" .

up: check
	@set -euo pipefail; \
	$(MOUNT_HELPERS) \
	load_mounts; \
	container system status >/dev/null 2>&1 || container system start; \
	if $(CONTAINER_RUNNING); then \
		echo "Container '$$NAME' is already running."; \
		if (( $${#volumes[@]} )); then echo "WARNING: requested mounts are not applied to an already-running container; run 'make restart' to recreate it." >&2; fi; \
		echo "noVNC:  $(NOVNC_URL)"; exit 0; \
	fi; \
	if ! $(IMAGE_EXISTS); then $(MAKE) --no-print-directory build; fi; \
	if $(CONTAINER_EXISTS); then echo "Removing stale container '$$NAME'..."; container delete "$$NAME" >/dev/null 2>&1 || true; fi; \
	echo "Starting container '$$NAME'..."; \
	container run --detach --rm \
		--name "$$NAME" \
		--cpus "$$CPUS" \
		--memory "$$MEMORY" \
		--publish "$$HOST_IP:$$PORT:6080" \
		--env "VNC_GEOMETRY=$$VNC_GEOMETRY" \
		--env "VNC_DEPTH=$$VNC_DEPTH" \
		--env "VNC_PASSWORD=$$VNC_PASSWORD" \
		--env "MOUNT_TARGETS=$$mount_targets" \
		"$${volumes[@]}" \
		"$$IMAGE" >/dev/null; \
	echo "Container '$$NAME' started."; \
	echo "noVNC:  $(NOVNC_URL)"

down:
	@if $(CONTAINER_RUNNING); then \
		echo "Stopping container '$$NAME'..."; container stop "$$NAME" >/dev/null 2>&1 || true; \
	else echo "Container '$$NAME' is not running."; fi

restart:
	@$(MAKE) --no-print-directory down
	@$(MAKE) --no-print-directory up

status:
	@echo "Container: $$NAME"; \
	if $(CONTAINER_RUNNING); then echo "Status:    running"; echo "noVNC:     $(NOVNC_URL)"; \
	elif $(CONTAINER_EXISTS); then echo "Status:    stopped (stale container present)"; exit 1; \
	else echo "Status:    not running"; exit 1; fi

clean: down
	@if $(CONTAINER_EXISTS); then container delete "$$NAME" >/dev/null 2>&1 || true; fi
	@echo "Clean complete."

clean-image: clean
	@if $(IMAGE_EXISTS); then container image delete "$$IMAGE" >/dev/null 2>&1 || true; fi
	@echo "Image clean complete."

shell: check
	@set -euo pipefail; \
	container system status >/dev/null 2>&1 || container system start; \
	if $(CONTAINER_RUNNING); then exec container exec --interactive --tty "$$NAME" /bin/bash; fi; \
	if ! $(IMAGE_EXISTS); then echo "ERROR: image '$$IMAGE' not found. Run 'make build' first." >&2; exit 1; fi; \
	exec container run --rm --interactive --tty --entrypoint /bin/bash "$$IMAGE"
