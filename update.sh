#!/bin/bash
set -euo pipefail

# Upgrades all containers using the rust-dev image to the latest built image.
# Preserves container name, port mappings, volumes, and environment variables.
# Data in named volumes is preserved across the upgrade.

IMAGE_NAME="rust-dev"
BUILD=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE_NAME="$2"; shift 2 ;;
        --build) BUILD=true; shift ;;
        *) echo "Usage: $0 [--image NAME] [--build]"; exit 1 ;;
    esac
done

if [ "$BUILD" = "true" ]; then
    echo "==> Rebuilding '${IMAGE_NAME}' image..."
    make -C "$SCRIPT_DIR" build
    echo ""
    NEW_IMAGE_ID=$(docker inspect --format='{{.Id}}' "$IMAGE_NAME")
else
    # Find the latest built image for this name from Docker history
    NEW_IMAGE_ID=$(docker images --no-trunc --format '{{.ID}}' "$IMAGE_NAME" | head -1)
    if [ -z "$NEW_IMAGE_ID" ]; then
        echo "==> No existing image '${IMAGE_NAME}' found. Run with 'build' to create one."
        exit 1
    fi
    echo "==> Using existing image '${IMAGE_NAME}' ($NEW_IMAGE_ID)."
fi

UPDATED=0
SKIPPED=0

for NAME in $(docker ps -a --format '{{.Names}}'); do
    CONTAINER_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$NAME")
    [ "$CONTAINER_IMAGE" != "$IMAGE_NAME" ] && continue

    CURRENT_IMAGE_ID=$(docker inspect --format='{{.Image}}' "$NAME")
    if [ "$CURRENT_IMAGE_ID" = "$NEW_IMAGE_ID" ]; then
        echo "==> '${NAME}' already using latest image, skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "==> Upgrading '${NAME}'..."
    WAS_RUNNING=$(docker inspect --format='{{.State.Running}}' "$NAME")
    SSH_PORT=$(docker inspect --format='{{with (index .HostConfig.PortBindings "22/tcp")}}{{if .}}{{(index . 0).HostPort}}{{end}}{{end}}' "$NAME")

    if [ -n "$SSH_PORT" ]; then
        # Clear old SSH key for this port
        echo "==> Clearing old SSH key for [localhost]:${SSH_PORT}..."
        ssh-keygen -R "[localhost]:${SSH_PORT}" 2>/dev/null || true
    fi

    MISC_ARGS=()
    CONTAINER_HOSTNAME=$(docker inspect --format='{{.Config.Hostname}}' "$NAME")
    [ -n "$CONTAINER_HOSTNAME" ] && MISC_ARGS+=(--hostname "$CONTAINER_HOSTNAME")
    [ "$(docker inspect --format='{{.HostConfig.Init}}' "$NAME")" = "true" ] && MISC_ARGS+=(--init)

    # Collect port bindings into array
    PORT_ARGS=()
    while IFS= read -r port; do
        [ -n "$port" ] && PORT_ARGS+=(-p "$port")
    done < <(docker inspect --format='{{range $p, $conf := .HostConfig.PortBindings}}{{if $conf}}{{(index $conf 0).HostPort}}:{{$p}}{{println}}{{end}}{{end}}' "$NAME" | sed 's|/[a-z]*$||')

    # Collect volume mounts into array
    VOL_ARGS=()
    while IFS= read -r vol; do
        [ -n "$vol" ] && VOL_ARGS+=(-v "$vol")
    done < <(docker inspect --format='{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}}{{if not .RW}}:ro{{end}}{{println}}{{end}}' "$NAME")

    # Collect environment variables into array (exclude Docker defaults)
    ENV_ARGS=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in PATH=*|HOME=*|HOSTNAME=*) continue ;; esac
        ENV_ARGS+=(-e "$line")
    done < <(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$NAME")

    docker stop "$NAME" >/dev/null 2>&1 || true
    docker rm "$NAME" >/dev/null

    docker create --name "$NAME" \
        ${MISC_ARGS[@]+"${MISC_ARGS[@]}"} \
        ${PORT_ARGS[@]+"${PORT_ARGS[@]}"} \
        ${VOL_ARGS[@]+"${VOL_ARGS[@]}"} \
        ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
        "$IMAGE_NAME" >/dev/null

    if [ "$WAS_RUNNING" = "true" ]; then
        docker start "$NAME" >/dev/null
    fi

    echo "  Done (was $( [ "$WAS_RUNNING" = "true" ] && echo "running" || echo "stopped"))."
    UPDATED=$((UPDATED + 1))
done

echo ""
if [ "$UPDATED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
    echo "==> No containers using image '${IMAGE_NAME}' found."
else
    echo "==> ${UPDATED} upgraded, ${SKIPPED} skipped."
fi
