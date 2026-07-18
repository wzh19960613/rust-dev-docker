# rust-dev-docker

[![Build and Push Docker Image](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml/badge.svg)](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml)

A multi-architecture (amd64 + arm64) Docker image for Rust development, with optional tooling for AI coding assistants, Node.js, Zsh, and Python.

中文文档：[README_CN.md](./README_CN.md)

---

## Prebuilt image

Multi-arch images are built automatically via GitHub Actions and published to GitHub Container Registry:

**`ghcr.io/wzh19960613/rust-dev:latest`**

- Architectures: `linux/amd64`, `linux/arm64` (auto-selected by Docker)
- Built from this repo on every push to `main`

### Pull

```bash
# Public package — pull directly
docker pull ghcr.io/wzh19960613/rust-dev:latest
```

### Run

```bash
# Prepare secrets (SSH password + optional ZhiPu API key)
mkdir -p ./secrets
echo "your_ssh_password" > ./secrets/ssh_password
echo "your_zhipu_api_key" > ./secrets/zp_key   # optional

# Start the container
docker run -d \
  -p 2222:22 \
  -v "$PWD/secrets:/run/secrets:ro" \
  -v rust-dev-data:/root/workspace \
  ghcr.io/wzh19960613/rust-dev:latest

# Connect via SSH
ssh -p 2222 root@localhost
```

---

## What's inside

Based on the official `rust:latest` image, with these preinstalled:

- **Rust toolchain**: `rustc`, `cargo`, `rustfmt`, `clippy`, `rust-analyzer`
- **SSH server**: password auth enabled, configurable via mounted secret
- **Node.js**: via NodeSource (default: latest LTS)
- **Zsh**: set as root's default login shell (SSH sessions land in zsh)
- **Python 3**: with `pip` and `venv`
- **AI coding tools** (opt-in at build time): Claude Code, OpenCode, Codex

All tools can be toggled or version-pinned via build args (see below).

---

## Build configuration

The Dockerfile accepts build args. Three of them — `NODE`, `ZSH`, `PYTHON` — share a uniform "tri-state" semantic:

| Value | Meaning |
|---|---|
| `false` | Not installed |
| `true` | Install the latest version |
| `<version-string>` | Install the specified version |

### Build arguments

| Arg | Default | Description |
|---|---|---|
| `RUST_TAG` | `latest` | Tag of the base `rust` image |
| `SSH` | `true` | Install & enable the SSH server |
| `NODE` | `true` | Node.js: `true` / `false` / `22` / `22.5.0` |
| `ZSH` | `true` | Zsh: `true` / `false` / `5.9` (apt pin) |
| `PYTHON` | `true` | Python: `true` / `false` / `3.11` |
| `CLAUDE_CODE` | `false` | Install Claude Code |
| `CODEX` | `false` | Install OpenAI Codex |
| `OPENCODE` | `false` | Install OpenCode + oh-my-opencode |
| `APT_MIRROR` | _(empty)_ | e.g. `https://mirrors.tuna.tsinghua.edu.cn` |
| `BUILD_PROXY` | _(empty)_ | HTTP/HTTPS/All proxy used during the build |
| `GIT_USER` | _(empty)_ | `git config --global user.name` |
| `GIT_EMAIL` | _(empty)_ | `git config --global user.email` |

### Examples

```bash
# Defaults: full image with SSH + Node + Zsh + Python
docker build -t rust-dev .

# Pin specific versions
docker build \
  --build-arg NODE=22 \
  --build-arg ZSH=5.9 \
  --build-arg PYTHON=3.11 \
  -t rust-dev:custom .

# Minimal: Rust only, no extras
docker build --build-arg NODE=false --build-arg ZSH=false --build-arg PYTHON=false -t rust-dev:slim .

# Behind a proxy + Tsinghua apt mirror
docker build \
  --build-arg BUILD_PROXY=http://your-proxy:port \
  --build-arg APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn \
  -t rust-dev .
```

---

## Building from source

### Using Make

```bash
cp .arg.example .arg       # edit values to taste
make init-secrets          # create ./secrets with placeholder values
make build                 # build the image
make run                   # run a container
make ssh                   # SSH into the running container
```

Other Make targets: `stop`, `rm`, `clean`, `shell`.

### Using the container helper

`container.sh` creates named containers with persistent volumes and can seed a project directory into `/root/workspace`:

```bash
./container.sh --dir /path/to/your/project --ssh 2222
./container.sh --name my-dev --ssh 2223
./container.sh --base-name                  # name = "rust-dev"
```

Options: `--dir/-d`, `--name/-n`, `--full-name/-f`, `--base-name`, `--ssh/-s`, `--proxy/-p`, `--volume/-v`.

---

## Secrets

Secrets are read from files mounted at `/run/secrets` (read-only). Two files are supported:

| File | Required | Purpose |
|---|---|---|
| `ssh_password` | Yes (when SSH enabled) | Sets the root password for SSH login |
| `zp_key` | No | ZhiPu API key for AI assistant auth |

See [`secrets.example/`](./secrets.example) for placeholders. **Never commit real secrets** — the `secrets/` directory is gitignored.

On startup, `entrypoint.sh`:

1. Picks `npx` (if Node present) or `bunx` as the JS runtime, configurable via `-e USE_NODE=false`
2. Authenticates ZhiPu and reloads Claude Code / OpenCode if installed
3. Starts the SSH server

---

## Upgrading existing containers

`update.sh` rebuilds the image and recreates all containers that use it, preserving name, ports, volumes, and environment:

```bash
./update.sh --build         # rebuild + upgrade all containers
./update.sh                 # upgrade to the most recently built image
```

---

## CI / Multi-arch build

[`.github/workflows/docker.yml`](./.github/workflows/docker.yml) builds `linux/amd64` + `linux/arm64` in parallel via QEMU + Buildx on every push to `main`, and pushes a single multi-arch manifest to GHCR. Manual runs are also supported (Actions tab → "Run workflow"), with an optional extra tag.

---

## License

Provided as-is for personal development use.
