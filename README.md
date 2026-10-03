# rust-dev-docker

[![Build and Push Docker Image](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml/badge.svg)](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml)

A multi-architecture (amd64 + arm64) Docker image for Rust development, with optional tooling for AI coding assistants, Node.js, Zsh, Python, WASM and Android targets.

中文文档：[README_CN.md](./README_CN.md)

---

## Prebuilt image

Multi-arch images are built automatically via GitHub Actions and published to GitHub Container Registry. Every build is tagged with the Rust version it contains, and a daily scheduled job rebuilds automatically when a new Rust stable is released.

| Tag | Content |
|---|---|
| `latest` / `rust-<ver>` | Rust + SSH + Node.js + Zsh + Python |
| `slim` / `slim-rust-<ver>` | Rust + SSH only |
| `wasm` / `wasm-rust-<ver>` | `latest` + wasm32/WASI targets + wasm-pack |
| `android` / `android-rust-<ver>` | `latest` + Android rustup targets (linking needs an external NDK) |

For example: `ghcr.io/wzh19960613/rust-dev:latest`, `ghcr.io/wzh19960613/rust-dev:rust-1.99.0`, `ghcr.io/wzh19960613/rust-dev:wasm`.

- Architectures: `linux/amd64`, `linux/arm64` (auto-selected by Docker)
- Rebuilt on every push to `main`, and daily for new Rust stable releases
- Branches matching `ci/**` build with a `-ci-<branch>` tag suffix and never overwrite `latest`

### Pull & run

```bash
# Prepare secrets (SSH password + optional ZhiPu API key)
mkdir -p ./secrets
echo "your_ssh_password" > ./secrets/ssh_password
echo "your_zhipu_api_key" > ./secrets/zp_key   # optional

# Start the container (--hostname makes the shell prompt show the container name)
docker run -d \
  --name rust-dev \
  --hostname rust-dev \
  --init \
  -p 2222:22 \
  -v "$PWD/secrets:/run/secrets:ro" \
  -v rust-dev-data:/root/workspace \
  ghcr.io/wzh19960613/rust-dev:latest

# Connect via SSH
ssh -p 2222 root@localhost
```

`./container.sh` (see below) passes `--hostname` and `--init` automatically.

---

## What's inside

Based on the official `rust` image, with these preinstalled:

- **Rust toolchain**: `rustc`, `cargo`, `rustfmt`, `clippy`, `rust-analyzer`
- **SSH server**: password auth enabled, configurable via mounted secret
- **Node.js**: via NodeSource (default: latest LTS)
- **Zsh**: set as root's default login shell (SSH sessions land in zsh)
- **Python 3**: with `pip` and `venv`
- **WASM / Android targets**: opt-in at build time (see below)
- **AI coding tools** (opt-in at build time): Claude Code, OpenCode, Codex

### Shell experience

SSH sessions land in a properly configured zsh (not a bare one):

- Tab completion with a selection menu (`compinit`), case-insensitive matching
- Persistent history across sessions — stored in `/root/workspace` when that path is a volume, so it survives container upgrades
- Colored prompt `user@container path (git-branch)` — shows the container name when you pass `--hostname`
- Home/End/Delete/Ctrl+Arrow keys bound for common terminals, `ls`/`grep` colors
- `C.UTF-8` locale everywhere (no quoted/escaped output for non-ASCII filenames), and `COLORTERM` is accepted from your SSH client for true-color CLIs

Environment (cargo on `PATH`, `RUSTUP_HOME`, `CARGO_HOME`, `LANG`) is set via `/etc/zsh/zshenv` and `/etc/profile.d/`, so it also applies to non-interactive shells and `docker exec`.

---

## Build configuration

The Dockerfile accepts build args. `NODE`, `ZSH`, `PYTHON` share a "tri-state" semantic; `WASM` and `ANDROID` use named levels:

| Value (`NODE`/`ZSH`/`PYTHON`) | Meaning |
|---|---|
| `false` | Not installed |
| `true` | Install the latest version |
| `<version-string>` | Install the specified version |

| Value (`WASM`/`ANDROID`) | Meaning |
|---|---|
| `false` | Not included |
| `targets` | rustup targets only (wasm32 + WASI, or the 4 Android ABIs) |
| `tools` (WASM only) | `targets` + `wasm-pack` |

### Build arguments

| Arg | Default | Description |
|---|---|---|
| `RUST_TAG` | `latest` | Tag of the base `rust` image |
| `SSH` | `true` | Install & enable the SSH server |
| `NODE` | `true` | Node.js: `true` / `false` / `22` / `22.5.0` |
| `ZSH` | `true` | Zsh: `true` / `false` / `5.9` (apt pin) |
| `PYTHON` | `true` | Python: `true` / `false` / `3.11` |
| `WASM` | `false` | WASM: `false` / `targets` / `tools` |
| `ANDROID` | `false` | Android: `false` / `targets` (linking needs an external NDK) |
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

# With WASM tooling and Android targets
docker build --build-arg WASM=tools --build-arg ANDROID=targets -t rust-dev:cross .

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
make run                   # run a container (with --hostname/--init and a data volume)
make ssh                   # SSH into the running container
```

Other Make targets: `stop`, `rm`, `clean`, `shell`.

### Using the container helper

`container.sh` is the recommended way to run dev containers. It labels containers, picks a free SSH port automatically when `--ssh` is omitted, sets `--hostname`/`--init`/`--restart unless-stopped`, persists data in a named volume, and maintains SSH aliases:

```bash
./container.sh --dir /path/to/your/project   # name & alias: rust-dev-<dirname>
./container.sh --name my-dev                 # alias: my-dev
./container.sh --image ghcr.io/wzh19960613/rust-dev:wasm --name my-wasm
./container.sh ls                            # list containers: port, variant, dir
./container.sh sync --name my-dev --dir .    # re-push host code into the container
./container.sh prune                         # remove stopped containers (--volumes also drops their data)
```

After creating/updating containers, `ssh <container-name>` just works: the script maintains `~/.ssh/rust-dev-containers.conf` and a one-time managed `Include` block in `~/.ssh/config`. Use the alias as the remote host in VS Code / Zed / your editor of choice — no more port juggling.

Create options: `--dir/-d`, `--name/-n`, `--full-name/-f`, `--base-name`, `--ssh/-s` (default: first free port from 2222), `--proxy/-p`, `--volume/-v`, `--image/-i` (default `rust-dev`; a GHCR tag records the variant for `update.sh`).

---

## Secrets

Secrets are read from files mounted at `/run/secrets` (read-only). Two files are supported:

| File | Required | Purpose |
|---|---|---|
| `ssh_password` | Yes (when SSH enabled) | Sets the root password for SSH login |
| `ssh_authorized_keys` | No | Public keys appended to `/root/.ssh/authorized_keys` for passwordless login |
| `zp_key` | No | ZhiPu API key for AI assistant auth |

See [`secrets.example/`](./secrets.example) for placeholders. **Never commit real secrets** — the `secrets/` directory is gitignored.

On startup, `entrypoint.sh`:

1. Authenticates ZhiPu and reloads Claude Code / OpenCode if installed (non-fatal: the container still boots if auth fails, e.g. offline)
2. Redirects `~/.npm-global`, `~/.npm`, `~/.bun` and `~/.local` into the persistent workspace volume — CLI tools installed later (`npm i -g`, `cargo install`, the Claude installer, …) survive container recreation, and `npm_config_prefix`/`CARGO_INSTALL_ROOT` are preset so installs land there automatically
3. Installs `ssh_authorized_keys` when present, writes proxy environment into `/etc/environment` for SSH sessions
4. Starts the SSH server and re-execs into `sleep infinity` as PID 1

Secrets are never echoed to container logs.

---

## Upgrading existing containers

`update.sh` recreates containers on newer images, preserving name, hostname, ports, volumes, environment, labels and restart policy. By default it pulls each container's variant from GHCR (as recorded by `container.sh --image`), so together with the daily CI rebuild one command upgrades every container to the newest Rust:

```bash
./update.sh                 # pull each container's GHCR variant + recreate
./update.sh --build         # rebuild the local image + upgrade local containers
./update.sh --local         # upgrade local containers to the last local build
./update.sh --image NAME    # like --local, against a custom image name
```

A Docker `HEALTHCHECK` (sshd reachability) is built into the image, so unhealthy containers show up in `docker ps` / `./container.sh ls`.

---

## CI / Multi-arch build

[`.github/workflows/docker.yml`](./.github/workflows/docker.yml):

- On every push to `main`, builds all four variants (`latest`, `slim`, `wasm`, `android`) in parallel for `linux/amd64` + `linux/arm64` via QEMU + Buildx, and pushes them to GHCR with Rust-version tags (e.g. `rust-1.99.0`, `wasm-rust-1.99.0`)
- A daily scheduled job checks for a new Rust stable release and rebuilds only when one is found (skips if the version tag already exists)
- Pushes to `ci/**` branches also build, tagged with a `-ci-<branch>` suffix so `latest` is never touched by test builds
- A `smoke` job boots every variant and verifies over real SSH: zsh login shell, `C.UTF-8` locale, backspace key binding, completion loading, `ls` colors, hostname, cargo on `PATH`, and per-variant contents (wasm targets, Android targets, …)

Manual runs are also supported (Actions tab → "Run workflow"), with an optional extra tag for the full image.

---

## License

Provided as-is for personal development use.
