#!/bin/bash
set -eu

export PATH="/usr/local/cargo/bin:${HOME}/.local/bin:${HOME}/.bun/bin:${PATH}"

# ZhiPu authentication and setup
if [ -f /run/secrets/zp_key ]; then
    # Choose JS runtime: prefer npx (Node) when available, fall back to bunx.
    # Override with -e USE_NODE=false to force bunx.
    USE_NODE="${USE_NODE:-}"
    RUNX=""
    if [ "$USE_NODE" = "false" ]; then
        RUNX="bunx"
    elif [ "$USE_NODE" = "true" ]; then
        RUNX="npx"
    elif command -v npx >/dev/null 2>&1; then
        RUNX="npx"
    elif command -v bunx >/dev/null 2>&1; then
        RUNX="bunx"
    fi

    if [ -z "$RUNX" ]; then
        echo "Warning: ZhiPu auth skipped, neither 'npx' nor 'bunx' is available" >&2
    else
        echo "==> Using JS runtime: $RUNX"
        ZP_KEY=$(cat /run/secrets/zp_key)
        if ! "$RUNX" @z_ai/coding-helper auth glm_coding_plan_china "$ZP_KEY"; then
            echo "Warning: ZhiPu authentication failed" >&2
        fi

        setup_claude_models() {
            local key="$1" value="$2" file="$3"
            if grep -q "\"$key\"" "$file"; then
                sed -i "s|\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"$key\": \"$value\"|g" "$file"
            else
                sed -i "/\"env\"[[:space:]]*:[[:space:]]*{/a\\    \"$key\": \"$value\"," "$file"
            fi
        }

        # Auto-detect and reload Claude Code if installed
        if command -v claude >/dev/null 2>&1; then
            "$RUNX" @z_ai/coding-helper auth reload claude
            SETTINGS_FILE="$HOME/.claude/settings.json"
            if [ -f "$SETTINGS_FILE" ]; then
                setup_claude_models "ANTHROPIC_DEFAULT_HAIKU_MODEL" "glm-4.5-air" "$SETTINGS_FILE"
                setup_claude_models "ANTHROPIC_DEFAULT_SONNET_MODEL" "glm-5.1" "$SETTINGS_FILE"
                setup_claude_models "ANTHROPIC_DEFAULT_OPUS_MODEL" "glm-5.1" "$SETTINGS_FILE"
                echo "==> Updated GLM models in Claude settings"
            fi
        fi

        # Auto-detect and reload OpenCode if installed
        if command -v opencode >/dev/null 2>&1; then
            "$RUNX" @z_ai/coding-helper auth reload opencode
            sed -i 's/zhipuai-coding-plan\/glm-4.6/zhipuai-coding-plan\/glm-5.1/g' \
                "$HOME/.config/opencode/opencode.json"
        fi
    fi
fi

# Configure proxy for SSH sessions (inherit from docker env, applied by pam_env)
if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
    echo "==> Configuring proxy for SSH sessions..."
    {
        [ -n "${HTTP_PROXY:-}" ] && printf 'HTTP_PROXY="%s"\nhttp_proxy="%s"\n' "$HTTP_PROXY" "$HTTP_PROXY"
        [ -n "${HTTPS_PROXY:-}" ] && printf 'HTTPS_PROXY="%s"\nhttps_proxy="%s"\n' "$HTTPS_PROXY" "$HTTPS_PROXY"
        [ -n "${NO_PROXY:-}" ] && printf 'NO_PROXY="%s"\nno_proxy="%s"\n' "$NO_PROXY" "$NO_PROXY"
    } >> /etc/environment
fi

# Start SSH server if enabled
if [ "${SSH:-true}" = "true" ]; then
    if [ ! -f /run/secrets/ssh_password ]; then
        echo "Error: /run/secrets/ssh_password not found" >&2
        exit 1
    fi
    echo "root:$(cat /run/secrets/ssh_password)" | chpasswd
    mkdir -p /run/sshd
    /usr/sbin/sshd -e
    echo "==> SSH server started on port 22"
else
    echo "==> SSH disabled, container running in background mode"
fi

exec sleep infinity
