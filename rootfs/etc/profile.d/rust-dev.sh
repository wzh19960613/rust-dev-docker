case ":$PATH:" in
  *:/usr/local/cargo/bin:*) ;;
  *) export PATH="/usr/local/cargo/bin:$PATH" ;;
esac
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export LANG=C.UTF-8
