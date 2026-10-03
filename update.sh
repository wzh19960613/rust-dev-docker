#!/bin/bash
set -euo pipefail

# Upgrades rust-dev containers to newer images, preserving name, hostname,
# ports, volumes, environment, labels and restart policy.
#
#   ./update.sh                 # pull each container's variant from GHCR
#   ./update.sh --build         # rebuild local image + upgrade local containers
#   ./update.sh --local         # upgrade local containers to the last build
#   ./update.sh --image NAME    # like --local, with a custom image name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHCR_IMAGE="ghcr.io/wzh19960613/rust-dev"
IMAGE_NAME="rust-dev"
SOURCE="ghcr"
BUILD=false

while [ $# -gt 0 ]; do
    case "$1" in
        --local) SOURCE="local"; shift ;;
        --build) SOURCE="local"; BUILD=true; shift ;;
        --image) SOURCE="local"; IMAGE_NAME="$2"; shift 2 ;;
        *) echo "Usage: $0 [--build | --local | --image NAME]"; exit 1 ;;
    esac
done

if [ "$SOURCE" = "local" ]; then
    if [ "$BUILD" = "true" ]; then
        echo "==> Rebuilding '${IMAGE_NAME}'..."
        make -C "$SCRIPT_DIR" build
    fi
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 \
        || { echo "==> Image '${IMAGE_NAME}' not found. Run with --build."; exit 1; }
fi

PULLED=""

collect_and_recreate() { # NAME NEW_REF
    local name=$1 new_ref=$2
    local SSH_PORT
    SSH_PORT=$(docker inspect -f '{{with (index .HostConfig.PortBindings "22/tcp")}}{{if .}}{{(index . 0).HostPort}}{{end}}{{end}}' "$name")
    [ -z "$SSH_PORT" ] || ssh-keygen -R "[localhost]:${SSH_PORT}" >/dev/null 2>&1 || true

    local MISC_ARGS=() PORT_ARGS=() VOL_ARGS=() ENV_ARGS=() LABEL_ARGS=()
    local v
    v=$(docker inspect -f '{{.Config.Hostname}}' "$name"); [ -n "$v" ] && MISC_ARGS+=(--hostname "$v")
    [ "$(docker inspect -f '{{.HostConfig.Init}}' "$name")" = "true" ] && MISC_ARGS+=(--init)
    v=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")
    [ "$v" != "no" ] && [ -n "$v" ] && MISC_ARGS+=(--restart "$v")
    while IFS= read -r line; do
        case "${line%%=*}" in rustdev*) LABEL_ARGS+=(--label "$line") ;; esac
    done < <(docker inspect -f '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' "$name")
    while IFS= read -r port; do
        [ -n "$port" ] && PORT_ARGS+=(-p "$port")
    done < <(docker inspect -f '{{range $p, $conf := .HostConfig.PortBindings}}{{if $conf}}{{(index $conf 0).HostPort}}:{{$p}}{{println}}{{end}}{{end}}' "$name" | sed 's|/[a-z]*$||')
    while IFS= read -r vol; do
        [ -n "$vol" ] && VOL_ARGS+=(-v "$vol")
    done < <(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}}{{if not .RW}}:ro{{end}}{{println}}{{end}}' "$name")
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in PATH=*|HOME=*|HOSTNAME=*) continue ;; esac
        ENV_ARGS+=(-e "$line")
    done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name")

    docker stop "$name" >/dev/null 2>&1 || true
    docker rm "$name" >/dev/null
    docker create --name "$name" \
        ${MISC_ARGS[@]+"${MISC_ARGS[@]}"} \
        ${LABEL_ARGS[@]+"${LABEL_ARGS[@]}"} \
        ${PORT_ARGS[@]+"${PORT_ARGS[@]}"} \
        ${VOL_ARGS[@]+"${VOL_ARGS[@]}"} \
        ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
        "$new_ref" >/dev/null
}

pull_once() { # REF -> image id (empty when pull fails)
    case " $PULLED " in *" $1 "*) ;; *)
        echo "==> Pulling $1..."
        docker pull -q "$1" && PULLED=" $PULLED $1 " || true
        ;;
    esac
    docker image inspect -f '{{.Id}}' "$1" 2>/dev/null || true
}

target_for() { # NAME -> "<new-ref> <new-id-or-empty>" based on source mode
    local name=$1 label_img runtime_img ref id
    label_img=$(docker inspect -f '{{index .Config.Labels "rustdev.image"}}' "$name")
    runtime_img=$(docker inspect -f '{{.Config.Image}}' "$name")
    if [ "$SOURCE" = "ghcr" ]; then
        case "${label_img:-$runtime_img}" in
            "${GHCR_IMAGE}":*) ref="${label_img}" ;;
            *) return 1 ;;
        esac
        id=$(pull_once "$ref")
    else
        { [ "$runtime_img" = "$IMAGE_NAME" ] || [ "$label_img" = "$IMAGE_NAME" ]; } || return 1
        ref="$IMAGE_NAME"
        id=$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME")
    fi
    printf '%s %s' "$ref" "$id"
}

UPDATED=0
SKIPPED=0
SEEN=0

for NAME in $(docker ps -a --format '{{.Names}}'); do
    TARGET=$(target_for "$NAME") || continue
    SEEN=$((SEEN + 1))
    NEW_REF=${TARGET%% *}
    NEW_ID=${TARGET#* }
    [ -n "$NEW_ID" ] || { echo "==> '${NAME}': image unavailable, skipping."; continue; }

    CURRENT_ID=$(docker inspect -f '{{.Image}}' "$NAME")
    if [ "$CURRENT_ID" = "$NEW_ID" ]; then
        echo "==> '${NAME}' already on ${NEW_REF}, skipping."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo "==> Upgrading '${NAME}' to ${NEW_REF}..."
    WAS_RUNNING=$(docker inspect -f '{{.State.Running}}' "$NAME")
    collect_and_recreate "$NAME" "$NEW_REF"
    [ "$WAS_RUNNING" = "true" ] && docker start "$NAME" >/dev/null
    echo "  Done (was $( [ "$WAS_RUNNING" = "true" ] && echo running || echo stopped))."
    UPDATED=$((UPDATED + 1))
done

[ "$UPDATED" -gt 0 ] && bash "${SCRIPT_DIR}/ssh-config.sh" regen

echo ""
if [ "$SEEN" -eq 0 ]; then
    echo "==> No managed containers found."
    echo "    (containers created with ./container.sh, or using image '${IMAGE_NAME}' with --local)"
else
    echo "==> ${UPDATED} upgraded, ${SKIPPED} skipped."
fi
