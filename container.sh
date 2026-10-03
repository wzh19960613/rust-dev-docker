#!/bin/bash
set -euo pipefail

# Creates and manages rust-dev containers (data persists in named volumes).
#
#   ./container.sh [--dir PATH] [--name NAME | --full-name NAME | --base-name]
#                  [--image REF] [--volume VOL] [--ssh PORT] [--proxy URL]
#   ./container.sh sync  --name NAME --dir PATH   # re-push host code
#   ./container.sh ls                            # list rust-dev containers
#   ./container.sh prune [--volumes]             # remove stopped ones
#
# After create/update, `ssh <container-name>` works via the managed include
# block in ~/.ssh/config (see ssh-config.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"
DEFAULT_IMAGE="rust-dev"
BASE_PORT=2222

die() { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

port_in_use() { nc -z localhost "$1" >/dev/null 2>&1; }

free_port_from() {
    local p
    for p in $(seq "$1" $((100 + ${1}))); do
        port_in_use "$p" || { echo "$p"; return 0; }
    done
    die "no free port in ${1}..$((100 + ${1}))"
}

variant_of_image() {
    case "$1" in
        *:*) printf '%s' "${1##*:}" ;;
        *)   printf 'local' ;;
    esac
}

sanitize_hostname() {
    local h
    h=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9.-' '-')
    case "$h" in
        ''|[^a-z0-9]*) h="h${h}" ;;
    esac
    printf '%s' "$h"
}

ensure_git_artifacts() {
    local dir=$1
    if [ ! -f "${dir}/.gitignore" ]; then
        info "No .gitignore found, creating a basic one..."
        printf 'target/\n**/*.rs.bk\nCargo.lock\n.idea/\n.vscode/\n*.swp\n.DS_Store\nbuild/\ndist/\n' \
            > "${dir}/.gitignore"
    fi
    if [ ! -d "${dir}/.git" ]; then
        info "Not a git repository, initializing..."
        (cd "${dir}" && git init -q)
    fi
}

# Packs DIR (git-tracked + untracked non-ignored, minus macOS metadata).
pack_workspace() {
    local dir=$1 tmp=$2
    export COPYFILE_DISABLE=1
    (cd "${dir}" && {
        git ls-files -z
        git ls-files -z --others --exclude-standard
    } | rsync -a --delete --files-from=- --from0 \
        --exclude='._*' --exclude='.DS_Store' --exclude='Thumbs.db' \
        --exclude='.[cC][fF]' --exclude='.[dD][sS]_[sS][tT][oO][rR][eE]' \
        "${dir}/" "${tmp}/")
    tar --no-xattrs --no-mac-metadata --exclude='._*' --exclude='.DS_Store' \
        --exclude='.[cC][fF]' --exclude='.[dD][sS]_[sS][tT][oO][rR][eE]' \
        -czf "${tmp}/workspace.tar.gz" -C "${tmp}" .
}

pack_and_copy() { # CONTAINER DIR (works on created containers)
    local container=$1 dir=$2 tmp
    tmp=$(mktemp -d)
    ensure_git_artifacts "${dir}"
    pack_workspace "${dir}" "${tmp}"
    docker cp "${tmp}/workspace.tar.gz" "${container}:/tmp/workspace.tar.gz"
    rm -rf "${tmp}"
}

extract_workspace() { # CONTAINER DIRNAME (container must be running)
    docker exec "$1" sh -c \
        "mkdir -p /root/workspace/$2 && cd /root/workspace/$2 && tar --no-same-permissions --no-same-owner -xzf /tmp/workspace.tar.gz && rm /tmp/workspace.tar.gz"
}

cmd_ls() {
    local name status variant port dir
    printf '%-30s %-26s %-8s %-6s %s\n' NAME STATUS VARIANT PORT WORKDIR
    while IFS=$'\t' read -r name status variant port dir; do
        [ -n "$name" ] || continue
        printf '%-30s %-26s %-8s %-6s %s\n' \
            "$name" "$status" "${variant:-local}" "${port:-?}" "${dir:--}"
    done < <(docker ps -a --filter "label=rustdev=1" \
        --format '{{.Names}}\t{{.Status}}\t{{.Label "rustdev.variant"}}\t{{.Label "rustdev.port"}}\t{{.Label "rustdev.dir"}}')
}

cmd_sync() {
    local name="" dir=""
    while [ $# -gt 0 ]; do
        case $1 in
            --name|-n) name=$2; shift 2 ;;
            --dir|-d)  dir=$2; shift 2 ;;
            *) die "sync: unknown option $1" ;;
        esac
    done
    [ -n "$name" ] && [ -n "$dir" ] || die "sync requires --name NAME --dir PATH"
    [ -d "$dir" ] || die "Directory '$dir' does not exist"
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)" = true ] \
        || die "Container '$name' is not running (start it first)"
    info "Syncing '${dir}' into ${name}..."
    pack_and_copy "$name" "$dir"
    extract_workspace "$name" "$(basename "$dir")"
    info "Done: /root/workspace/$(basename "$dir")"
}

cmd_prune() {
    local remove_volumes=false name vol count=0
    [ "${1:-}" = "--volumes" ] && remove_volumes=true
    while IFS=$'\t' read -r name vol; do
        [ -n "$name" ] || continue
        info "Removing stopped container '${name}'"
        docker rm "$name" >/dev/null
        if [ "$remove_volumes" = true ] && [ -n "$vol" ]; then
            docker volume rm "$vol" >/dev/null 2>&1 || true
        fi
        count=$((count + 1))
    done < <(docker ps -a --filter "label=rustdev=1" --filter "status=exited" \
        --filter "status=created" --format '{{.Names}}\t{{.Label "rustdev.volume"}}')
    [ "$count" -gt 0 ] && info "Removed ${count} container(s)" || info "Nothing to prune"
    bash "${SCRIPT_DIR}/ssh-config.sh" regen
}

cmd_create() {
    local dir_path="" ssh_port="" volume_name="" container_name=""
    local full_name="" name_source="" proxy_url="" image="${DEFAULT_IMAGE}"
    while [ $# -gt 0 ]; do
        case $1 in
            --dir|-d)       dir_path=$2; shift 2 ;;
            --name|-n)      [ -z "$name_source" ] || die "--name/--full-name/--base-name are mutually exclusive"
                            name_source="--name"; container_name=$2; shift 2 ;;
            --full-name|-f) [ -z "$name_source" ] || die "--name/--full-name/--base-name are mutually exclusive"
                            name_source="--full-name"; full_name=$2; shift 2 ;;
            --base-name)    [ -z "$name_source" ] || die "--name/--full-name/--base-name are mutually exclusive"
                            name_source="--base-name"; full_name="rust-dev"; shift ;;
            --ssh|-s)       ssh_port=$2; shift 2 ;;
            --volume|-v)    volume_name=$2; shift 2 ;;
            --proxy|-p)     proxy_url=$2; shift 2 ;;
            --image|-i)     image=$2; shift 2 ;;
            *)              die "unknown option $1" ;;
        esac
    done

    if [ -n "$full_name" ]; then container_name="$full_name"; fi
    if [ -z "$container_name" ]; then
        if [ -z "$dir_path" ]; then
            container_name="rust-dev-$(head -c 4 /dev/urandom | xxd -p)"
            info "No directory specified, creating container without initial data"
        else
            container_name="rust-dev-$(basename "$dir_path")"
        fi
    fi
    volume_name="${CUSTOM_VOLUME:-${volume_name:-${container_name}}}"

    [ -z "$dir_path" ] || [ -d "$dir_path" ] || die "Directory '$dir_path' does not exist"
    [ -d "$SECRETS_DIR" ] || die "Secrets dir '$SECRETS_DIR' missing (see secrets.example/)"
    if docker ps -a --format '{{.Names}}' | grep -qx "${container_name}"; then
        die "Container '${container_name}' already exists (docker rm -f ${container_name})"
    fi

    if [ -n "$ssh_port" ]; then
        port_in_use "$ssh_port" && die "Port ${ssh_port} is already in use"
    else
        ssh_port=$(free_port_from "$BASE_PORT")
    fi

    if [ -z "$proxy_url" ]; then
        local arg_file="${SCRIPT_DIR}/.arg"
        [ -f "$arg_file" ] && { set -a; . "$arg_file"; set +a; proxy_url="${RUN_PROXY:-}"; }
    fi

    info "Container name: ${container_name}"
    info "SSH port: ${ssh_port} | image: ${image} | volume: ${volume_name}"
    ssh-keygen -R "[localhost]:${ssh_port}" >/dev/null 2>&1 || true

    local label_args=(--label rustdev=1
        --label "rustdev.image=${image}"
        --label "rustdev.variant=$(variant_of_image "${image}")"
        --label "rustdev.port=${ssh_port}"
        --label "rustdev.volume=${volume_name}")
    [ -n "$dir_path" ] && label_args+=(--label "rustdev.dir=${dir_path}")

    local proxy_args=()
    if [ -n "$proxy_url" ]; then
        info "Using proxy: ${proxy_url}"
        proxy_args=(-e "HTTP_PROXY=${proxy_url}" -e "http_proxy=${proxy_url}"
            -e "HTTPS_PROXY=${proxy_url}" -e "https_proxy=${proxy_url}")
    fi

    docker create --name "${container_name}" \
        --hostname "$(sanitize_hostname "${container_name}")" \
        --init --restart unless-stopped \
        "${label_args[@]}" \
        -p "${ssh_port}:22" \
        -v "${SECRETS_DIR}:/run/secrets:ro" \
        -v "${volume_name}:/root/workspace" \
        ${proxy_args[@]+"${proxy_args[@]}"} \
        "$image" >/dev/null

    [ -z "$dir_path" ] || pack_and_copy "${container_name}" "${dir_path}"
    docker start "${container_name}" >/dev/null
    [ -z "$dir_path" ] || extract_workspace "${container_name}" "$(basename "${dir_path}")"
    bash "${SCRIPT_DIR}/ssh-config.sh" regen
    info "Container '${container_name}' is ready: ssh ${container_name}"
}

case "${1:-}" in
    ls)    shift; cmd_ls "$@" ;;
    sync)  shift; cmd_sync "$@" ;;
    prune) shift; cmd_prune "$@" ;;
    "")    echo "Usage: $0 [ls | sync | prune | <create-flags>]" >&2; exit 1 ;;
    *)     cmd_create "$@" ;;
esac
