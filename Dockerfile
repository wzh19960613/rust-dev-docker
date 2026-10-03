# syntax=docker/dockerfile:1
# Build:
#   docker build -t rust-dev .
#   docker build --build-arg APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn -t rust-dev .
# Prepare secrets:
#   mkdir -p ./secrets
#   echo "your_password" > ./secrets/ssh_password
#   echo "your_zhipu_key" > ./secrets/zp_key
# Run:
#   docker run -d --name rust-dev --hostname rust-dev --init \
#     -p 2222:22 -v ./secrets:/run/secrets:ro rust-dev
# Connect via SSH (prompt shows the container name via --hostname):
#   ssh -p 2222 root@localhost

ARG RUST_TAG=latest
FROM rust:${RUST_TAG}

SHELL ["/bin/bash", "-euc"]

ARG BUILD_PROXY=""
ARG TARGETARCH=""
ARG SSH=true
ARG CLAUDE_CODE=false
ARG CODEX=false
ARG OPENCODE=false
# NODE/ZSH/PYTHON accept: false | true (latest) | <version-string>
ARG NODE=true
ARG ZSH=true
ARG PYTHON=true
# WASM accepts: false | targets (wasm32 + WASI std) | tools (targets + wasm-pack)
ARG WASM=false
# ANDROID accepts: false | targets (rustup android ABIs; linking needs an external NDK)
ARG ANDROID=false
ARG APT_MIRROR=""
ARG GIT_USER=""
ARG GIT_EMAIL=""

ENV LANG=C.UTF-8

LABEL org.opencontainers.image.title="rust-dev" \
      org.opencontainers.image.description="Multi-arch Rust dev container with SSH, zsh, Node and Python" \
      org.opencontainers.image.source="https://github.com/wzh19960613/rust-dev-docker"

RUN <<'EOS'
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
if [ -n "${APT_MIRROR:-}" ]; then
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sed -i "s|http://deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources
    elif [ -f /etc/apt/sources.list ]; then
        sed -i "s|http://archive.ubuntu.com|$APT_MIRROR|g" /etc/apt/sources.list
        sed -i "s|http://security.ubuntu.com|$APT_MIRROR|g" /etc/apt/sources.list
    fi
fi
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl less ncurses-term
rm -rf /var/lib/apt/lists/*
EOS

RUN <<'EOS'
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
rustup component add rustfmt clippy rust-analyzer

case "${WASM:-false}" in
    targets|tools)
        rustup target add wasm32-unknown-unknown wasm32-wasip1 wasm32-wasip2
        ;;
esac
if [ "${WASM:-false}" = "tools" ]; then
    case "${TARGETARCH:-}" in
        arm64) WP_ARCH=aarch64 ;;
        *)     WP_ARCH=x86_64 ;;
    esac
    WP_VER=$(curl -fsSL https://api.github.com/repos/wasm-bindgen/wasm-pack/releases/latest \
        | grep -oP '"tag_name":\s*"\K[^"]+' || true)
    WP_VER=${WP_VER:-v0.15.0}
    curl -fsSL -o /tmp/wasm-pack.tgz \
        "https://github.com/wasm-bindgen/wasm-pack/releases/download/${WP_VER}/wasm-pack-${WP_VER}-${WP_ARCH}-unknown-linux-musl.tar.gz"
    tar -xzf /tmp/wasm-pack.tgz -C /tmp
    install -m 0755 "/tmp/wasm-pack-${WP_VER}-${WP_ARCH}-unknown-linux-musl/wasm-pack" /usr/local/bin/wasm-pack
    rm -rf /tmp/wasm-pack*
fi

if [ "${ANDROID:-false}" = "targets" ]; then
    rustup target add aarch64-linux-android armv7-linux-androideabi \
        x86_64-linux-android i686-linux-android
fi
EOS

RUN <<'EOS'
[ "${SSH:-true}" = "true" ] || exit 0
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
apt-get update
apt-get install -y --no-install-recommends openssh-server
rm -rf /var/lib/apt/lists/*
mkdir -p /var/run/sshd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
printf 'AcceptEnv LANG LC_* COLORTERM\nClientAliveInterval 120\n' >> /etc/ssh/sshd_config
EOS

# Install Node.js via NodeSource, or bun as fallback when NODE is disabled.
# NODE accepts: false | true (latest LTS) | <major> (e.g. 22) | <full> (e.g. 22.5.0)
RUN <<'EOS'
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
case "${NODE:-true}" in
    false)
        if [ "${CODEX:-false}" = "true" ] || [ "${OPENCODE:-false}" = "true" ] || [ "${CLAUDE_CODE:-false}" = "true" ]; then
            echo "==> NODE disabled; installing bun as JS runtime..."
            curl -fsSL https://bun.sh/install | bash
            echo 'export PATH="$HOME/.bun/bin:$PATH"' >> /root/.bashrc
        fi
        ;;
    *)
        if [ "${NODE:-true}" = "true" ]; then
            echo "==> Installing Node.js (latest LTS via NodeSource)..."
            SETUP=https://deb.nodesource.com/setup_lts.x
        else
            NODE_MAJOR="${NODE%%.*}"
            echo "==> Installing Node.js ${NODE} via NodeSource..."
            SETUP="https://deb.nodesource.com/setup_${NODE_MAJOR}.x"
        fi
        curl -fsSL "$SETUP" | bash -
        if echo "${NODE:-true}" | grep -qE '[0-9]\.[0-9]'; then
            apt-get install -y --no-install-recommends "nodejs=${NODE}-1*"
        else
            apt-get install -y --no-install-recommends nodejs
        fi
        rm -rf /var/lib/apt/lists/*
        ;;
esac
EOS

# Install Zsh and set it as root's login shell; config comes from rootfs/.
# ZSH accepts: false | true (apt default) | <version> (apt pin, e.g. 5.9)
RUN <<'EOS'
case "${ZSH:-true}" in
    false) exit 0 ;;
    true)  ZSH_VERSION="" ;;
    *)     ZSH_VERSION="${ZSH}" ;;
esac
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
echo "==> Installing zsh..."
apt-get update
if [ -n "$ZSH_VERSION" ]; then
    apt-get install -y --no-install-recommends "zsh=${ZSH_VERSION}-*" || {
        echo "ERROR: zsh version ${ZSH_VERSION} not available in apt repository"; exit 1; }
else
    apt-get install -y --no-install-recommends zsh
fi
rm -rf /var/lib/apt/lists/*
chsh -s "$(command -v zsh)" root
EOS

# Shell/login environment (zsh + bash), layered AFTER the zsh install so dpkg
# never sees our /etc/zsh/zshenv as a foreign conffile.
COPY rootfs/ /

RUN <<'EOS'
cat >> /root/.bashrc <<'RC'
case ":$PATH:" in
  *:/usr/local/cargo/bin:*) ;;
  *) export PATH="/usr/local/cargo/bin:$PATH" ;;
esac
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
RC
EOS

# PYTHON accepts: false | true (apt python3 + pip + venv) | <minor> (e.g. 3.11)
RUN <<'EOS'
case "${PYTHON:-false}" in
    false) exit 0 ;;
    true)  PYTHON_VERSION="" ;;
    *)     PYTHON_VERSION="${PYTHON}" ;;
esac
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
echo "==> Installing python..."
apt-get update
if [ -n "$PYTHON_VERSION" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        "python${PYTHON_VERSION}" "python${PYTHON_VERSION}-venv" python3-pip || {
        echo "ERROR: python ${PYTHON_VERSION} not available in apt repository"; exit 1; }
    ln -sf "/usr/bin/python${PYTHON_VERSION}" /usr/local/bin/python
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv
    ln -sf /usr/bin/python3 /usr/local/bin/python
fi
rm -rf /var/lib/apt/lists/*
EOS

RUN <<'EOS'
[ "${OPENCODE:-false}" = "true" ] || exit 0
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
echo "==> Installing OpenCode..."
curl -fsSL https://opencode.ai/install | bash
echo "==> Installing oh-my-opencode..."
if [ "${NODE:-true}" != "false" ]; then
    npx -y oh-my-opencode install --no-tui --claude=no --gemini=no --copilot=no
else
    export PATH="$HOME/.bun/bin:$PATH"
    bunx oh-my-opencode install --no-tui --claude=no --gemini=no --copilot=no
fi
EOS

RUN <<'EOS'
[ "${CODEX:-false}" = "true" ] || exit 0
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
echo "==> Installing Codex..."
if [ "${NODE:-true}" != "false" ]; then
    npm install -g @openai/codex
else
    export PATH="$HOME/.bun/bin:$PATH"
    bun install -g @openai/codex
fi
EOS

RUN <<'EOS'
[ "${CLAUDE_CODE:-false}" = "true" ] || exit 0
if [ -n "${BUILD_PROXY:-}" ]; then
    export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"
fi
echo "==> Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
head -1 /tmp/claude-install.sh | grep -qE '^#!' || { echo "ERROR: claude install script is not a valid shell script"; exit 1; }
bash /tmp/claude-install.sh
for RC in /root/.bashrc /root/.zshrc; do
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    echo 'alias claude_yolo="IS_SANDBOX=1 claude --dangerously-skip-permissions"' >> "$RC"
done
EOS

RUN if [ -n "$GIT_USER" ]; then git config --global user.name "$GIT_USER"; fi && \
    if [ -n "$GIT_EMAIL" ]; then git config --global user.email "$GIT_EMAIL"; fi

EXPOSE 22 8080

# Secrets volume (mount ./secrets directory here containing ssh_password and zp_key files)
VOLUME ["/run/secrets"]

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

# sshd reachable when SSH enabled; always healthy otherwise
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["bash", "-c", "[ \"${SSH:-true}\" != true ] || exec 3<>/dev/tcp/127.0.0.1/22"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
