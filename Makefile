.DEFAULT_GOAL := help
SHELL := /bin/sh

-include .env

IMAGE ?= linux-desktop:latest
NAME ?= linux-desktop
HOST_IP ?= 127.0.0.1
PORT ?= 6080
CPUS ?= 4
MEMORY ?= 4G
VNC_GEOMETRY ?= 1440x900
VNC_DEPTH ?= 24
VNC_PASSWORD ?= apple
MIN_MACOS_MAJOR ?= 26

export IMAGE NAME HOST_IP PORT CPUS MEMORY VNC_GEOMETRY VNC_DEPTH VNC_PASSWORD MIN_MACOS_MAJOR

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
		'' \
		'Configuration is read from .env when present, with Makefile defaults otherwise.'

check:
	@set -eu; \
	arch=$$(uname -m 2>/dev/null || printf unknown); \
	case "$$arch" in arm64|aarch64) : ;; *) echo "ERROR: Apple silicon (arm64) is required; detected $$arch." >&2; exit 1 ;; esac; \
	os=$$(uname -s 2>/dev/null || printf unknown); \
	if [ "$$os" != Darwin ]; then echo "ERROR: macOS is required; detected $$os." >&2; exit 1; fi; \
	if command -v sw_vers >/dev/null 2>&1; then \
		version=$$(sw_vers -productVersion 2>/dev/null || printf unknown); \
		major=$${version%%.*}; \
		case "$$major" in ''|*[!0-9]*) echo "WARNING: could not determine macOS version; continuing." >&2 ;; \
		*) if [ "$$major" -lt "$$MIN_MACOS_MAJOR" ]; then echo "ERROR: macOS $$MIN_MACOS_MAJOR or later is required; detected $$version." >&2; exit 1; fi ;; \
		esac; \
	else \
		echo "WARNING: sw_vers is unavailable; continuing without macOS version validation." >&2; \
	fi; \
	command -v container >/dev/null 2>&1 || { echo "ERROR: Apple 'container' CLI was not found in PATH." >&2; exit 1; }

doctor:
	@set -eu; \
	echo "== linux-desktop doctor =="; \
	if $(MAKE) --no-print-directory check; then echo "[ OK ] Platform prerequisites"; else echo "[FAIL] Platform prerequisites"; exit 1; fi; \
	if container system status >/dev/null 2>&1; then echo "[ OK ] Apple container system: running"; else echo "[WARN] Apple container system: not running; 'up' will start it"; fi; \
	if [ "$$VNC_PASSWORD" = apple ]; then echo "[WARN] VNC_PASSWORD: still set to the default value"; else echo "[ OK ] VNC_PASSWORD: overridden from the default"; fi

build: check
	container build --platform linux/arm64 --tag "$$IMAGE" .

up: check
	@set -eu; \
	container system status >/dev/null 2>&1 || container system start; \
	if container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then \
		echo "Container '$$NAME' is already running."; \
		if [ "$$HOST_IP" = 0.0.0.0 ]; then host=localhost; else host="$$HOST_IP"; fi; \
		echo "noVNC:  http://$$host:$$PORT/vnc.html"; \
		exit 0; \
	fi; \
	if ! container image list --quiet 2>/dev/null | grep -Fx "$$IMAGE" >/dev/null; then \
		$(MAKE) --no-print-directory build; \
	fi; \
	if container list --all --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then \
		echo "Removing stale container '$$NAME'..."; \
		container delete "$$NAME" >/dev/null 2>&1 || true; \
	fi; \
	echo "Starting container '$$NAME'..."; \
	container run --detach --rm \
		--name "$$NAME" \
		--cpus "$$CPUS" \
		--memory "$$MEMORY" \
		--publish "$$HOST_IP:$$PORT:6080" \
		--env "VNC_GEOMETRY=$$VNC_GEOMETRY" \
		--env "VNC_DEPTH=$$VNC_DEPTH" \
		--env "VNC_PASSWORD=$$VNC_PASSWORD" \
		"$$IMAGE" >/dev/null; \
	if [ "$$HOST_IP" = 0.0.0.0 ]; then host=localhost; else host="$$HOST_IP"; fi; \
	echo "Container '$$NAME' started."; \
	echo "noVNC:  http://$$host:$$PORT/vnc.html"

down:
	@set -eu; \
	if container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then \
		echo "Stopping container '$$NAME'..."; \
		container stop "$$NAME" >/dev/null 2>&1 || true; \
	else \
		echo "Container '$$NAME' is not running."; \
	fi

restart: check
	@$(MAKE) --no-print-directory down
	@$(MAKE) --no-print-directory up

status:
	@set -eu; \
	if container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then running=true; else running=false; fi; \
	if [ "$$HOST_IP" = 0.0.0.0 ]; then host=localhost; else host="$$HOST_IP"; fi; \
	echo "Container: $$NAME"; \
	if [ "$$running" = true ]; then echo "Status:    running"; echo "noVNC:     http://$$host:$$PORT/vnc.html"; \
	elif container list --all --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then echo "Status:    stopped (stale container present)"; \
	else echo "Status:    not running"; fi; \
	[ "$$running" = true ]

clean:
	@set -eu; \
	if container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then container stop "$$NAME" >/dev/null 2>&1 || true; fi; \
	if container list --all --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then container delete "$$NAME" >/dev/null 2>&1 || true; fi; \
	echo "Clean complete."

clean-image: clean
	@set -eu; \
	if container image list --quiet 2>/dev/null | grep -Fx "$$IMAGE" >/dev/null; then container image delete "$$IMAGE" >/dev/null 2>&1 || true; fi; \
	echo "Image clean complete."

shell: check
	@set -eu; \
	container system status >/dev/null 2>&1 || container system start; \
	if container list --quiet 2>/dev/null | grep -Fx "$$NAME" >/dev/null; then \
		exec container exec --interactive --tty "$$NAME" /bin/bash; \
	fi; \
	if ! container image list --quiet 2>/dev/null | grep -Fx "$$IMAGE" >/dev/null; then echo "ERROR: image '$$IMAGE' not found. Run 'make build' first." >&2; exit 1; fi; \
	exec container run --rm --interactive --tty --entrypoint /bin/bash "$$IMAGE"
