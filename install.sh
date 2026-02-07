#!/bin/sh
set -eu

REPO_OWNER="zippyy"
REPO_NAME="glinet-spitz-ax-signal-stats"
BRANCH="main"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

BIN_URL="${RAW_BASE}/openwrt/bin/glinet-spitz-ax-signal-stats"

SERVICE_NAME="glinet-spitz-ax-signal-stats"
BIN_PATH="/root/${SERVICE_NAME}"
INIT_PATH="/etc/init.d/${SERVICE_NAME}"
CONF_PATH="/etc/config/${SERVICE_NAME}"

DEFAULT_PORT="8080"

say() { printf "%s\n" "$*"; }
die() { say "ERROR: $*"; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root."
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  url="$1"
  out="$2"

  if have_cmd wget; then
    wget -qO "$out" "$url" || return 1
    return 0
  fi

  if have_cmd uclient-fetch; then
    uclient-fetch -qO "$out" "$url" || return 1
    return 0
  fi

  if have_cmd curl; then
    curl -fsSL "$url" -o "$out" || return 1
    return 0
  fi

  return 1
}

banner() {
  say "========================================"
  say " Spitz AX Signal Stats – Installer"
  say "========================================"
  say ""
}

prompt_port() {
  printf "HTTP port [%s]: " "$DEFAULT_PORT"
  read -r port || true
  [ -n "${port:-}" ] || port="$DEFAULT_PORT"

  case "$port" in
    *[!0-9]*|"") die "Port must be a number." ;;
  esac
  [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || die "Port out of range (1-65535)."
  echo "$port"
}

write_uci_config() {
  port="$1"

  # Create /etc/config entry (simple, portable)
  cat >"$CONF_PATH" <<EOF
config ${SERVICE_NAME} 'main'
  option enabled '1'
  option port '${port}'
EOF
}

detect_port_flag() {
  # Returns a best-guess flag, or empty if unknown.
  # We intentionally keep this lightweight and heuristic.
  help_out="$1"

  echo "$help_out" | grep -qiE '(^|[[:space:]])(--port|-port)([[:space:]=]|$)' && { echo "--port"; return 0; }
  echo "$help_out" | grep -qiE '(^|[[:space:]])(-p)([[:space:]=]|$)' && { echo "-p"; return 0; }
  echo "$help_out" | grep -qiE '(^|[[:space:]])(--listen)([[:space:]=]|$)' && { echo "--listen"; return 0; }
  echo "$help_out" | grep -qiE '(^|[[:space:]])(--addr|--address)([[:space:]=]|$)' && { echo "--addr"; return 0; }

  # no known flag
  echo ""
}

write_init_script() {
  cat >"$INIT_PATH" <<'EOF'
#!/bin/sh /etc/rc.common

START=95
STOP=10
USE_PROCD=1

NAME="glinet-spitz-ax-signal-stats"
BIN="/root/glinet-spitz-ax-signal-stats"
CONF="/etc/config/glinet-spitz-ax-signal-stats"

load_cfg() {
  PORT="8080"
  ENABLED="1"

  [ -f "$CONF" ] || return 0

  # Minimal parse: option port / enabled
  PORT="$(sed -n "s/^[[:space:]]*option[[:space:]]\+port[[:space:]]\+'\([^']*\)'.*/\1/p" "$CONF" | tail -n 1)"
  [ -n "$PORT" ] || PORT="8080"

  ENABLED="$(sed -n "s/^[[:space:]]*option[[:space:]]\+enabled[[:space:]]\+'\([^']*\)'.*/\1/p" "$CONF" | tail -n 1)"
  [ -n "$ENABLED" ] || ENABLED="1"
}

start_service() {
  load_cfg
  [ "$ENABLED" = "1" ] || return 0
  [ -x "$BIN" ] || return 0

  # Probe help output to find a port flag (best effort).
  HELP_OUT="$("$BIN" --help 2>&1 || true)"

  PORT_FLAG=""
  echo "$HELP_OUT" | grep -qiE '(^|[[:space:]])(--port|-port)([[:space:]=]|$)' && PORT_FLAG="--port"
  echo "$HELP_OUT" | grep -qiE '(^|[[:space:]])(-p)([[:space:]=]|$)' && [ -z "$PORT_FLAG" ] && PORT_FLAG="-p"
  echo "$HELP_OUT" | grep -qiE '(^|[[:space:]])(--listen)([[:space:]=]|$)' && [ -z "$PORT_FLAG" ] && PORT_FLAG="--listen"

  procd_open_instance
  procd_set_param command "$BIN"

  # If we found a port flag, pass it. If not, we run defaults.
  if [ -n "$PORT_FLAG" ]; then
    if [ "$PORT_FLAG" = "--listen" ]; then
      # common format: --listen :8080
      procd_append_param command "$PORT_FLAG" ":$PORT"
    else
      procd_append_param command "$PORT_FLAG" "$PORT"
    fi
  fi

  procd_set_param respawn 3600 5 5
  procd_close_instance
}

stop_service() {
  # procd handles this
  return 0
}
EOF

  chmod +x "$INIT_PATH"
}

install_everything() {
  need_root
  banner

  say "=== Configuration ==="
  PORT="$(prompt_port)"
  say ""

  say "Downloading binary to: $BIN_PATH"
  tmpbin="$(mktemp)"
  if ! fetch "$BIN_URL" "$tmpbin"; then
    rm -f "$tmpbin"
    die "Failed to download binary. URL: $BIN_URL"
  fi

  mv "$tmpbin" "$BIN_PATH"
  chmod +x "$BIN_PATH"

  say "Writing config to: $CONF_PATH"
  write_uci_config "$PORT"

  say "Installing init.d service to: $INIT_PATH"
  write_init_script

  say "Enabling + starting service..."
  "$INIT_PATH" enable >/dev/null 2>&1 || true
  "$INIT_PATH" restart >/dev/null 2>&1 || "$INIT_PATH" start >/dev/null 2>&1 || true

  say ""
  say "========================================"
  say " Installed successfully"
  say "----------------------------------------"
  say " Binary:   $BIN_PATH"
  say " Service:  $INIT_PATH (enabled)"
  say " Config:   $CONF_PATH"
  say ""
  say " Open (LAN only): http://<router-ip>:${PORT}/"
  say " Default GL.iNet: http://192.168.8.1:${PORT}/"
  say ""
  say "WARNING: Do NOT expose this port to the internet."
  say "========================================"
}

uninstall_everything() {
  need_root
  banner
  say "Stopping + disabling service..."
  [ -x "$INIT_PATH" ] && "$INIT_PATH" stop >/dev/null 2>&1 || true
  [ -x "$INIT_PATH" ] && "$INIT_PATH" disable >/dev/null 2>&1 || true

  say "Removing files..."
  rm -f "$INIT_PATH" "$BIN_PATH" "$CONF_PATH"

  say ""
  say "Uninstalled."
}

case "${1:-install}" in
  install) install_everything ;;
  uninstall) uninstall_everything ;;
  *) die "Usage: $0 [install|uninstall]" ;;
esac
