#!/bin/bash
set -euo pipefail

# Creates a new rust-dev container.
# If dir_path is provided, copies the directory into the container (respecting .gitignore).
# Data is persisted in a named volume, so it survives container removal.

DIR_PATH=""
SSH_PORT="2222"
VOLUME_NAME=""
CONTAINER_NAME=""
FULL_NAME=""
PROXY_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir|-d)
            DIR_PATH="$2"
            shift 2
            ;;
        --name|-n)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --full-name|-f)
            FULL_NAME="$2"
            shift 2
            ;;
        --base-name)
            FULL_NAME="rust-dev"
            shift
            ;;
        --ssh|-s)
            SSH_PORT="$2"
            shift 2
            ;;
        --proxy|-p)
            PROXY_URL="$2"
            shift 2
            ;;
        --volume|-v)
            VOLUME_NAME="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Usage: $0 [--dir PATH] [--name NAME | --full-name NAME | --base-name] [--volume VOLUME] [--ssh PORT] [--proxy URL]"
            exit 1
            ;;
    esac
done

# --name, --full-name, and --base-name are mutually exclusive
if [ -n "$CONTAINER_NAME" ] && [ -n "$FULL_NAME" ]; then
    echo "Error: --name, --full-name, and --base-name are mutually exclusive"
    exit 1
fi

# Determine container name
if [ -n "$FULL_NAME" ]; then
    CONTAINER_NAME="$FULL_NAME"
elif [ -z "$CONTAINER_NAME" ]; then
    if [ -z "$DIR_PATH" ]; then
        # No dir and no name provided, generate a random container name
        CONTAINER_NAME="rust-dev-$(head -c 4 /dev/urandom | xxd -p)"
        echo "==> No directory specified, creating container without initial data"
    else
        # Derive container name from directory name
        DIR_NAME=$(basename "$DIR_PATH")
        CONTAINER_NAME="rust-dev-${DIR_NAME}"
    fi
fi

VOLUME_NAME="${CUSTOM_VOLUME:-${CONTAINER_NAME}}"
echo "==> Container name: ${CONTAINER_NAME}"

# Check if directory exists (if dir_path is provided)
if [ -n "$DIR_PATH" ]; then
    if [ ! -d "$DIR_PATH" ]; then
        echo "Error: Directory '$DIR_PATH' does not exist"
        exit 1
    fi
fi

# Get the script directory (for secrets path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"

# Check if secrets directory exists
if [ ! -d "$SECRETS_DIR" ]; then
    echo "Error: Secrets directory '$SECRETS_DIR' does not exist"
    echo "Please create it and add required secrets (see secrets.example/)"
    exit 1
fi

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Error: Container '${CONTAINER_NAME}' already exists"
    echo "Remove it first with: docker rm -f ${CONTAINER_NAME}"
    exit 1
fi

# Create a temporary directory for rsync (only if DIR_PATH is set)
if [ -n "$DIR_PATH" ]; then
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT
    # Disable macOS resource fork copying
    export COPYFILE_DISABLE=1
fi

echo "==> Creating container '${CONTAINER_NAME}'..."
echo "==> Data volume: ${VOLUME_NAME}"

# Clear old SSH key for this port
echo "==> Clearing old SSH key for [localhost]:${SSH_PORT}..."
ssh-keygen -R "[localhost]:${SSH_PORT}" 2>/dev/null || true

# Build proxy environment variables
# Priority: --proxy > .arg file (RUN_PROXY)
PROXY_ENV=""

if [ -z "$PROXY_URL" ]; then
    # Load from .arg file if not specified via command line
    ARG_FILE="${SCRIPT_DIR}/.arg"
    if [ -f "$ARG_FILE" ]; then
        # Source the .arg file to get variables
        set -a
        source "$ARG_FILE"
        set +a
        PROXY_URL="${RUN_PROXY:-}"
    fi
fi

if [ -n "$PROXY_URL" ]; then
    PROXY_ENV="-e HTTP_PROXY=$PROXY_URL -e http_proxy=$PROXY_URL -e HTTPS_PROXY=$PROXY_URL -e https_proxy=$PROXY_URL"
    echo "==> Using proxy: ${PROXY_URL}"
fi

# Create the container with secrets mounted and data volume
docker create --name "${CONTAINER_NAME}" \
    -p "${SSH_PORT}:22" \
    -p "8080:8080" \
    -v "${SECRETS_DIR}:/run/secrets:ro" \
    -v "${VOLUME_NAME}:/root/workspace" \
    ${PROXY_ENV} \
    rust-dev

# Step 1: Check/create .gitignore (only if DIR_PATH is set)
if [ -n "$DIR_PATH" ]; then
    GITIGNORE_FILE="${DIR_PATH}/.gitignore"
    if [ ! -f "${GITIGNORE_FILE}" ]; then
        echo "==> No .gitignore found, creating a basic one..."
        cat > "${GITIGNORE_FILE}" << 'EOF'
# Rust
target/
**/*.rs.bk
Cargo.lock

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Build
build/
dist/
EOF
        echo "==> Created .gitignore at ${GITIGNORE_FILE}"
    fi

    # Step 2: Check if git repository, init if not
    GIT_DIR="${DIR_PATH}/.git"
    if [ ! -d "${GIT_DIR}" ]; then
        echo "==> Not a git repository, initializing..."
        cd "${DIR_PATH}"
        git init -q
        echo "==> Git repository initialized"
    fi

    # Step 3: Copy files using git ls-files (respects .gitignore properly)
    echo "==> Copying files (respecting .gitignore)..."
    cd "${DIR_PATH}"
    {
        git ls-files -z
        git ls-files -z --others --exclude-standard
    } | rsync -a --delete --files-from=- --from0 \
        --exclude='._*' --exclude='.DS_Store' --exclude='Thumbs.db' \
        --exclude='.[cC][fF]' --exclude='.[dD][sS]_[sS][tT][oO][rR][eE]' \
        "${DIR_PATH}/" "${TEMP_DIR}/"

    # Create tar from the filtered files (exclude macOS metadata files)
    tar --no-xattrs --no-mac-metadata --exclude='._*' --exclude='.DS_Store' \
        --exclude='.[cC][fF]' --exclude='.[dD][sS]_[sS][tT][oO][rR][eE]' \
        -czf "${TEMP_DIR}/workspace.tar.gz" -C "${TEMP_DIR}" .

    # Copy the tar archive to the container
    docker cp "${TEMP_DIR}/workspace.tar.gz" "${CONTAINER_NAME}:/tmp/workspace.tar.gz"
fi

# Start the container
echo "==> Starting container..."
docker start "${CONTAINER_NAME}"

# Extract files inside the container (only if DIR_PATH was provided)
if [ -n "$DIR_PATH" ]; then
    DIR_NAME=$(basename "$DIR_PATH")
    # Extract to a subfolder named after the directory
    docker exec "${CONTAINER_NAME}" sh -c "mkdir -p /root/workspace/${DIR_NAME} && cd /root/workspace/${DIR_NAME} && tar --no-same-permissions --no-same-owner -xzf /tmp/workspace.tar.gz && rm /tmp/workspace.tar.gz"
fi

echo "==> Container '${CONTAINER_NAME}' is ready!"
echo "==> Connect via SSH: ssh -p ${SSH_PORT} root@localhost"
