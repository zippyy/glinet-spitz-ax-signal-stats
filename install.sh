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
DEFAULT_LAN_ONLY="y"

die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Run as root."; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  url="$1"
  out="$2"

  if have_cmd wget; then
    wget -qO "$out" "$url" && return 0
  fi
  if have_cmd uclient-fetch; then
    uclient-fetch -qO "$out" "$url" && return 0
  fi
  if have_cmd curl; then
    curl -fsSL "$url" -o "$out" && return 0
  fi
  return 1
}

say() {
  if [ -w /dev/tty ]; then
    printf "%s\n" "$*" > /dev/tty
  else
    printf "%s\n" "$*"
  fi
}

ask() {
  prompt="$1"
  def="${2:-}"

  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    if [ -n "$def" ]; then
      printf "%s [%s]: " "$prompt" "$def" > /dev/tty
    else
      printf "%s: " "$prompt" > /dev/tty
    fi
    IFS= read -r ans < /dev/tty || ans=""
    printf "\n" > /dev/tty
  else
    if [ -n "$def" ]; then
      printf "%s [%s]: " "$prompt" "$def" >&2
    else
      printf "%s: " "$prompt" >&2
    fi
    IFS= read -r ans || ans=""
    printf "\n" >&2
  fi

  [ -n "${ans:-}" ] || ans="$def"
  printf "%s" "$ans"
}

ask_port() {
  def="${1:-8080}"

  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    printf "HTTP port [%s]: " "$def" > /dev/tty
    IFS= read -r raw < /dev/tty || raw=""
    printf "\n" > /dev/tty
  else
    printf "HTTP port [%s]: " "$def" >&2
    IFS= read -r raw || raw=""
    printf "\n" >&2
  fi

  [ -n "${raw:-}" ] || raw="$def"
  port="$(printf "%s" "$raw" | tr -cd '0-9')"

  [ -n "$port" ] || die "Port must be a number."
  [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || die "Port out of range (1-65535)."
  printf "%s" "$port"
}

ask_yn() {
  prompt="$1"
  def="${2:-y}"
  ans="$(ask "$prompt (y/n)" "$def")"
  ans="$(printf "%s" "$ans" | tr '[:upper:]' '[:lower:]')"
  case "$ans" in
    y|yes) printf "y" ;;
    n|no)  printf "n" ;;
    *) die "Please answer y or n." ;;
  esac
}

banner() {
  say "========================================"
  say " Spitz AX Signal Stats – Installer"
  say "========================================"
  say ""
}

get_router_ip() {
  # Prefer GL.iNet LAN IP if detectable, otherwise fall back to first non-loopback IPv4
  # 1) OpenWrt network.lan.ipaddr
  if have_cmd uci; then
    ip="$(uci -q get network.lan.ipaddr 2>/dev/null || true)"
    if [ -n "${ip:-}" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  # 2) ip addr show br-lan (common)
  if have_cmd ip; then
    ip="$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true)"
    if [ -n "${ip:-}" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  # 3) default route interface -> first IPv4 on it
  if have_cmd ip; then
    dev="$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
    if [ -n "${dev:-}" ]; then
      ip="$(ip -4 addr show "$dev" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true)"
      if [ -n "${ip:-}" ]; then
        printf "%s" "$ip"
        return 0
      fi
    fi
  fi

  # 4) any non-loopback IPv4
  if have_cmd ip; then
    ip="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127\.' | head -n1 || true)"
    if [ -n "${ip:-}" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  printf "%s" "192.168.8.1"
}

write_config() {
  port="$1"
  lanonly="$2"
  cat >"$CONF_PATH" <<EOF2
config ${SERVICE_NAME} 'main'
  option enabled '1'
  option port '${port}'
  option lan_only '${lanonly}'
EOF2
}

write_init_script() {
  cat >"$INIT_PATH" <<'EOF2'
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
  LAN_ONLY="y"

  [ -f "$CONF" ] || return 0

  PORT="$(sed -n "s/^[[:space:]]*option[[:space:]]\+port[[:space:]]\+'\([^']*\)'.*/\1/p" "$CONF" | tail -n 1)"
  [ -n "$PORT" ] || PORT="8080"

  ENABLED="$(sed -n "s/^[[:space:]]*option[[:space:]]\+enabled[[:space:]]\+'\([^']*\)'.*/\1/p" "$CONF" | tail -n 1)"
  [ -n "$ENABLED" ] || ENABLED="1"

  LAN_ONLY="$(sed -n "s/^[[:space:]]*option[[:space:]]\+lan_only[[:space:]]\+'\([^']*\)'.*/\1/p" "$CONF" | tail -n 1)"
  [ -n "$LAN_ONLY" ] || LAN_ONLY="y"
}

detect_port_flag() {
  help_out="$1"

  echo "$help_out" | grep -qiE '(^|[[:space:]])(--port|-port)([[:space:]=]|$)' && { echo "--port"; return 0; }
  echo "$help_out" | grep -qiE '(^|[[:space:]])(-p)([[:space:]=]|$)' && { echo "-p"; return 0; }
  echo "$help_out" | grep -qiE '(^|[[:space:]])(--listen)([[:space:]=]|$)' && { echo "--listen"; return 0; }

  echo ""
}

lan_only_firewall() {
  command -v uci >/dev/null 2>&1 || return 0

  allow_name="Allow-${NAME}-LAN"
  deny_name="Deny-${NAME}-WAN"

  if ! uci show firewall 2>/dev/null | grep -q "name='${allow_name}'"; then
    rule="$(uci add firewall rule)"
    uci set firewall."$rule".name="$allow_name"
    uci set firewall."$rule".src="lan"
    uci set firewall."$rule".dest_port="$PORT"
    uci set firewall."$rule".proto="tcp"
    uci set firewall."$rule".target="ACCEPT"
  fi

  if ! uci show firewall 2>/dev/null | grep -q "name='${deny_name}'"; then
    rule="$(uci add firewall rule)"
    uci set firewall."$rule".name="$deny_name"
    uci set firewall."$rule".src="wan"
    uci set firewall."$rule".dest_port="$PORT"
    uci set firewall."$rule".proto="tcp"
    uci set firewall."$rule".target="REJECT"
  fi

  uci commit firewall >/dev/null 2>&1 || true
  /etc/init.d/firewall restart >/dev/null 2>&1 || true
}

start_service() {
  load_cfg
  [ "$ENABLED" = "1" ] || return 0
  [ -x "$BIN" ] || return 0

  [ "$LAN_ONLY" = "y" ] && lan_only_firewall

  HELP_OUT="$("$BIN" --help 2>&1 || true)"
  PORT_FLAG="$(detect_port_flag "$HELP_OUT")"

  procd_open_instance
  procd_set_param command "$BIN"

  if [ -n "$PORT_FLAG" ]; then
    if [ "$PORT_FLAG" = "--listen" ]; then
      procd_append_param command "$PORT_FLAG" ":$PORT"
    else
      procd_append_param command "$PORT_FLAG" "$PORT"
    fi
  fi

  procd_set_param respawn 3600 5 5
  procd_close_instance
}
EOF2
  chmod +x "$INIT_PATH"
}

install_everything() {
  need_root
  banner

  say "=== Configuration ==="
  PORT="$(ask_port "$DEFAULT_PORT")"
  LAN_ONLY="$(ask_yn "Restrict access to LAN only (block WAN access to this port)?" "$DEFAULT_LAN_ONLY")"
  say "Using port: $PORT"
  [ "$LAN_ONLY" = "y" ] && say "Firewall: LAN-only enabled" || say "Firewall: LAN-only disabled"
  say ""

  say "Downloading binary..."
  tmpbin="$(mktemp)"
  if ! fetch "$BIN_URL" "$tmpbin"; then
    rm -f "$tmpbin"
    die "Failed to download binary: $BIN_URL"
  fi
  mv "$tmpbin" "$BIN_PATH"
  chmod +x "$BIN_PATH"

  say "Writing config..."
  write_config "$PORT" "$LAN_ONLY"

  say "Installing service..."
  write_init_script

  say "Enabling + starting..."
  "$INIT_PATH" enable >/dev/null 2>&1 || true
  "$INIT_PATH" restart >/dev/null 2>&1 || "$INIT_PATH" start >/dev/null 2>&1 || true

  ip="$(get_router_ip)"

  say ""
  say "========================================"
  say " Installed successfully"
  say "----------------------------------------"
  say " Binary:   $BIN_PATH"
  say " Service:  $INIT_PATH (enabled)"
  say " Config:   $CONF_PATH"
  say ""
  say " Open: http://${ip}:${PORT}/"
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

  say "Removing firewall rules (best-effort)..."
  if have_cmd uci; then
    allow_name="Allow-${SERVICE_NAME}-LAN"
    deny_name="Deny-${SERVICE_NAME}-WAN"
    for s in $(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.@rule\[[0-9]\+\]\)\.name=.*/\1/p" | sort -u); do
      n="$(uci -q get "$s.name" 2>/dev/null || true)"
      [ "$n" = "$allow_name" ] && uci delete "$s" >/dev/null 2>&1 || true
      [ "$n" = "$deny_name" ] && uci delete "$s" >/dev/null 2>&1 || true
    done
    uci commit firewall >/dev/null 2>&1 || true
    /etc/init.d/firewall restart >/dev/null 2>&1 || true
  fi

  say ""
  say "Uninstalled."
}

ACTION="install"
PORT_OVERRIDE="${PORT:-}"
LAN_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    install|uninstall) ACTION="$1"; shift ;;
    --port) shift; [ $# -gt 0 ] || die "--port requires a value"; PORT_OVERRIDE="$1"; shift ;;
    --port=*) PORT_OVERRIDE="${1#--port=}"; shift ;;
    --lan-only) LAN_OVERRIDE="y"; shift ;;
    --no-lan-only) LAN_OVERRIDE="n"; shift ;;
    *) shift ;;
  esac
done

if [ -n "${PORT_OVERRIDE:-}" ]; then
  DEFAULT_PORT="$(printf "%s" "$PORT_OVERRIDE" | tr -cd '0-9')"
  [ -n "$DEFAULT_PORT" ] || DEFAULT_PORT="8080"
fi
if [ -n "${LAN_OVERRIDE:-}" ]; then
  DEFAULT_LAN_ONLY="$LAN_OVERRIDE"
fi

case "$ACTION" in
  install) install_everything ;;
  uninstall) uninstall_everything ;;
  *) die "Usage: $0 [install|uninstall] [--port N] [--lan-only|--no-lan-only] or PORT=N" ;;
esac
