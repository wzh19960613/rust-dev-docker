case ":$PATH:" in
  *:/usr/local/cargo/bin:*) ;;
  *) export PATH="/usr/local/cargo/bin:$PATH" ;;
esac
[ -d "$HOME/.npm-global/bin" ] && case ":$PATH:" in
  *:"$HOME/.npm-global/bin":*) ;;
  *) export PATH="$HOME/.npm-global/bin:$PATH" ;;
esac
[ -d "$HOME/.local/bin" ] && case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export CARGO_INSTALL_ROOT="$HOME/.local"
export npm_config_prefix="$HOME/.npm-global"
export LANG=C.UTF-8
