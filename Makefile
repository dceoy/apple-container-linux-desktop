.DEFAULT_GOAL := help

-include .env

VARIANT ?= ai
CONTAINERFILE ?= Containerfile.$(VARIANT)
IMAGE ?= acld:$(VARIANT)
REMOTE_IMAGE ?= ghcr.io/dceoy/acld/$(VARIANT):latest
NAME ?= acld-$(VARIANT)
HOST_IP ?= 127.0.0.1
PORT ?= 6080
CPUS ?= 4
MEMORY ?= 4G
VNC_GEOMETRY ?= 1440x900
VNC_DEPTH ?= 24
VNC_PASSWORD ?= apple
HOST_MOUNTS_FILE ?=
MIN_MACOS_MAJOR ?= 26

export VARIANT CONTAINERFILE IMAGE REMOTE_IMAGE NAME HOST_IP PORT CPUS MEMORY VNC_GEOMETRY VNC_DEPTH VNC_PASSWORD HOST_MOUNTS_FILE MIN_MACOS_MAJOR
export CLI_VOLUMES

.PHONY: help check variants pull build up down status clean shell

help check variants pull build up down status clean shell:
	@./acld.sh $@
