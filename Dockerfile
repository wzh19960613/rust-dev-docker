# Build:
#   docker build -t rust-dev .
#   docker build --build-arg APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn -t rust-dev .
# Prepare secrets:
#   mkdir -p ./secrets
#   echo "your_password" > ./secrets/ssh_password
#   echo "your_zhipu_key" > ./secrets/zp_key
# Run:
#   docker run -d -p 2222:22 -v ./secrets:/run/secrets:ro rust-dev
# Connect via SSH:
#   ssh -p 2222 root@localhost

ARG RUST_TAG=latest
FROM rust:${RUST_TAG}

SHELL ["/bin/bash", "-c"]

ARG BUILD_PROXY=""

RUN if [ -n "$BUILD_PROXY" ]; then \
        export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
    fi; \
    rustup component add rustfmt clippy rust-analyzer

# Build arguments (must be re-declared after FROM)
ARG SSH=true
ARG CLAUDE_CODE=false
ARG CODEX=false
ARG OPENCODE=false
# NODE/ZSH/PYTHON accept: false | true (latest) | <version-string>
ARG NODE=true
ARG ZSH=true
ARG PYTHON=true
ARG APT_MIRROR=""
ARG GIT_USER=""
ARG GIT_EMAIL=""
# entrypoint auto-detects npx vs bunx; override at runtime via -e USE_NODE=false

# Configure apt mirror if provided
RUN if [ -n "$APT_MIRROR" ]; then \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i "s|http://deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; \
    elif [ -f /etc/apt/sources.list ]; then \
        sed -i "s|http://archive.ubuntu.com|$APT_MIRROR|g" /etc/apt/sources.list && \
        sed -i "s|http://security.ubuntu.com|$APT_MIRROR|g" /etc/apt/sources.list; \
    fi; \
fi

# Install base dependencies
RUN if [ -n "$BUILD_PROXY" ]; then \
        export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
    fi; \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$SSH" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing SSH server..." && \
        apt-get update && \
        apt-get install -y --no-install-recommends openssh-server && \
        rm -rf /var/lib/apt/lists/* && \
        mkdir -p /var/run/sshd && \
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
        echo "==> Preserving Docker ENV PATH in /etc/profile and ~/.bashrc..." && \
        sed -i '/^export PATH$/i # Append cargo bin if not already in PATH\ncase ":$PATH:" in\n  *:/usr/local/cargo/bin:*) ;;\n  *) PATH="/usr/local/cargo/bin:$PATH" ;;\nesac\n' /etc/profile && \
        echo 'export PATH="/usr/local/cargo/bin:$PATH"' >> /root/.bashrc && \
        echo 'export RUSTUP_HOME=/usr/local/rustup' >> /root/.bashrc && \
        echo 'export CARGO_HOME=/usr/local/cargo' >> /root/.bashrc; \
    fi

RUN if [ "$CLAUDE_CODE" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing Claude Code..." && \
        curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
        head -1 /tmp/claude-install.sh | grep -qE '^#!' || { echo "ERROR: claude install script is not a valid shell script"; exit 1; } && \
        bash /tmp/claude-install.sh && \
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc && \
        echo 'alias claude_yolo="IS_SANDBOX=1 claude --dangerously-skip-permissions"' >> /root/.bashrc; \
    fi

# Install Node.js via NodeSource, or bun as fallback when NODE is disabled.
# NODE accepts: false | true (latest LTS) | <major> (e.g. 22) | <full> (e.g. 22.5.0)
RUN case "${NODE:-true}" in \
        false) NODE_INSTALL=false ;; \
        true)  NODE_INSTALL=true; NODE_VERSION="" ;; \
        *)     NODE_INSTALL=true; NODE_VERSION="${NODE}" ;; \
    esac; \
    if [ "$NODE_INSTALL" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        if [ -z "$NODE_VERSION" ]; then \
            echo "==> Installing Node.js (latest LTS via NodeSource)..." && \
            curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -; \
        elif echo "$NODE_VERSION" | grep -qE '[0-9]\.[0-9]'; then \
            MAJOR="${NODE_VERSION%%.*}"; \
            echo "==> Installing Node.js ${NODE_VERSION} via NodeSource..." && \
            curl -fsSL "https://deb.nodesource.com/setup_${MAJOR}.x" | bash - && \
            apt-get install -y --no-install-recommends "nodejs=${NODE_VERSION}-1*"; \
        else \
            echo "==> Installing Node.js ${NODE_VERSION}.x via NodeSource..." && \
            curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -; \
        fi; \
        apt-get install -y --no-install-recommends nodejs && \
        rm -rf /var/lib/apt/lists/*; \
    elif { [ "$CODEX" = "true" ] || [ "$OPENCODE" = "true" ] || [ "$CLAUDE_CODE" = "true" ]; }; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> NODE disabled; installing bun as JS runtime..." && \
        curl -fsSL https://bun.sh/install | bash && \
        echo 'export PATH="$HOME/.bun/bin:$PATH"' >> /root/.bashrc; \
    fi

# Install Zsh (and set as root's default shell). No oh-my-zsh.
# ZSH accepts: false | true (apt default) | <version> (apt pin, e.g. 5.9)
RUN case "${ZSH:-false}" in \
        false) ZSH_INSTALL=false ;; \
        true)  ZSH_INSTALL=true;  ZSH_VERSION="" ;; \
        *)     ZSH_INSTALL=true;  ZSH_VERSION="${ZSH}" ;; \
    esac; \
    if [ "$ZSH_INSTALL" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing zsh..." && \
        apt-get update && \
        if [ -n "$ZSH_VERSION" ]; then \
            apt-get install -y --no-install-recommends "zsh=${ZSH_VERSION}-*" || { \
                echo "ERROR: zsh version ${ZSH_VERSION} not available in apt repository"; exit 1; }; \
        else \
            apt-get install -y --no-install-recommends zsh; \
        fi && \
        rm -rf /var/lib/apt/lists/* && \
        chsh -s "$(command -v zsh)" root && \
        { \
            echo 'export PATH="/usr/local/cargo/bin:$PATH"'; \
            echo 'export RUSTUP_HOME=/usr/local/rustup'; \
            echo 'export CARGO_HOME=/usr/local/cargo'; \
            echo '[[ ":$PATH:" != *":/usr/local/cargo/bin:"* ]] && export PATH="/usr/local/cargo/bin:$PATH"'; \
        } > /root/.zshrc; \
    fi

# Install Python.
# PYTHON accepts: false | true (apt default python3 + pip + venv) | <minor> (e.g. 3.11)
RUN case "${PYTHON:-false}" in \
        false) PYTHON_INSTALL=false ;; \
        true)  PYTHON_INSTALL=true;  PYTHON_VERSION="" ;; \
        *)     PYTHON_INSTALL=true;  PYTHON_VERSION="${PYTHON}" ;; \
    esac; \
    if [ "$PYTHON_INSTALL" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing python..." && \
        apt-get update && \
        if [ -n "$PYTHON_VERSION" ]; then \
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                "python${PYTHON_VERSION}" "python${PYTHON_VERSION}-venv" python3-pip || { \
                echo "ERROR: python ${PYTHON_VERSION} not available in apt repository"; exit 1; }; \
            ln -sf "/usr/bin/python${PYTHON_VERSION}" /usr/local/bin/python; \
        else \
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                python3 python3-pip python3-venv; \
            ln -sf /usr/bin/python3 /usr/local/bin/python; \
        fi && \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN case "${NODE:-true}" in \
        false) NODE_INSTALL=false ;; \
        *)     NODE_INSTALL=true ;; \
    esac; \
    if [ "$OPENCODE" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing OpenCode..." && \
        curl -fsSL https://opencode.ai/install | bash && \
        echo "==> Installing oh-my-opencode..." && \
        if [ "$NODE_INSTALL" = "true" ]; then \
            npx -y oh-my-opencode install --no-tui --claude=no --gemini=no --copilot=no; \
        else \
            export PATH="$HOME/.bun/bin:$PATH"; \
            bunx oh-my-opencode install --no-tui --claude=no --gemini=no --copilot=no; \
        fi; \
    fi

RUN case "${NODE:-true}" in \
        false) NODE_INSTALL=false ;; \
        *)     NODE_INSTALL=true ;; \
    esac; \
    if [ "$CODEX" = "true" ]; then \
        if [ -n "$BUILD_PROXY" ]; then \
            export http_proxy="$BUILD_PROXY" https_proxy="$BUILD_PROXY" all_proxy="$BUILD_PROXY"; \
        fi; \
        echo "==> Installing Codex..." && \
        if [ "$NODE_INSTALL" = "true" ]; then \
            npm install -g @openai/codex; \
        else \
            export PATH="$HOME/.bun/bin:$PATH"; \
            bun install -g @openai/codex; \
        fi; \
    fi

# Configure git user if provided
RUN if [ -n "$GIT_USER" ]; then git config --global user.name "$GIT_USER"; fi && \
    if [ -n "$GIT_EMAIL" ]; then git config --global user.email "$GIT_EMAIL"; fi

# Expose ports
EXPOSE 22 8080

# Secrets volume (mount ./secrets directory here containing ssh_password and zp_key files)
VOLUME ["/run/secrets"]

# Start SSH server and keep container running
# Reads secrets from /run/secrets/ directory (ssh_password, zp_key files)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
