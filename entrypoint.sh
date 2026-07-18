#!/bin/bash
set -eux

source /root/.bashrc

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
    echo "Error: neither 'npx' nor 'bunx' is available in PATH"
    exit 1
fi
echo "==> Using JS runtime: $RUNX"

# Configure proxy for SSH sessions (inherit from docker env)
if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
    echo "==> Configuring proxy for SSH sessions..."
    {
        [ -n "${HTTP_PROXY:-}" ] && echo "export HTTP_PROXY=$HTTP_PROXY" && echo "export http_proxy=$HTTP_PROXY"
        [ -n "${HTTPS_PROXY:-}" ] && echo "export HTTPS_PROXY=$HTTPS_PROXY" && echo "export https_proxy=$HTTPS_PROXY"
        [ -n "${NO_PROXY:-}" ] && echo "export NO_PROXY=$NO_PROXY" && echo "export no_proxy=$NO_PROXY"
    } >> /etc/environment
fi

# ZhiPu authentication and setup
if [ -f /run/secrets/zp_key ]; then
    echo "==> Running ZhiPu authentication..."
    ZP_KEY=$(cat /run/secrets/zp_key)
    "$RUNX" @z_ai/coding-helper auth glm_coding_plan_china "$ZP_KEY"

    # Auto-detect and reload Claude Code if installed
    if command -v claude >/dev/null 2>&1; then
        "$RUNX" @z_ai/coding-helper auth reload claude

        # Update GLM models in settings.json
        SETTINGS_FILE="$HOME/.claude/settings.json"
        if [ -f "$SETTINGS_FILE" ]; then
            # Helper function to add or replace JSON key-value
            update_json_var() {
                local key="$1"
                local value="$2"
                local file="$3"

                if grep -q "\"$key\"" "$file"; then
                    # Key exists, replace it
                    sed -i "s/\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"$key\": \"$value\"/g" "$file"
                else
                    # Key doesn't exist, add it to the env object
                    sed -i "/\"env\"[[:space:]]*:[[:space:]]*{/a\\    \"$key\": \"$value\"," "$file"
                fi
            }

            update_json_var "ANTHROPIC_DEFAULT_HAIKU_MODEL" "glm-4.5-air" "$SETTINGS_FILE"
            update_json_var "ANTHROPIC_DEFAULT_SONNET_MODEL" "glm-5.1" "$SETTINGS_FILE"
            update_json_var "ANTHROPIC_DEFAULT_OPUS_MODEL" "glm-5.1" "$SETTINGS_FILE"

            echo "==> Updated GLM models in Claude settings"
        fi
    fi

    # Auto-detect and reload OpenCode if installed
    if command -v opencode >/dev/null 2>&1; then
        "$RUNX" @z_ai/coding-helper auth reload opencode

        # Update GLM model to glm-5
        sed -i 's/zhipuai-coding-plan\/glm-4.6/zhipuai-coding-plan\/glm-5.1/g' "$HOME/.config/opencode/opencode.json"
    fi
fi

# Start SSH server if enabled
if [ "${SSH:-true}" = "true" ]; then
    if [ -f /run/secrets/ssh_password ]; then
        PASSWORD=$(cat /run/secrets/ssh_password)
        echo "root:${PASSWORD}" | chpasswd
        /usr/sbin/sshd
        echo "==> SSH server started on port 22"
    else
        echo "Error: /run/secrets/ssh_password not found"
        exit 1
    fi
else
    echo "==> SSH disabled, container running in background mode"
fi

# Keep container running
sleep infinity
