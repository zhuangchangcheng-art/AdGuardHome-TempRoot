#!/system/bin/sh
# AdGuard Home TempRoot Remake - service / activate logic
# Design for temporary root, learned from several same-origin modules:
#  - liuzq2002: iptables NAT 53 -> AGH, ProxyConfig for proxy modules
#  - twoone-3: fail-open - if AGH does not listen, do NOT apply redirect
#  - Ceromis: proxy compatibility only when proxy is actually in use,
#    restore when it stops (bridge does the App side, ProxyConfig the module side)
#  - 410154425: mode/config file, private DNS must be off for interception
# Differences from the original, all deliberate:
#  - NO skip on soft reboot: if AGH is already running, stop it and start
#    again with the current yaml, so a config change actually takes effect
#    without a hard reboot (which would lose temporary root).
#  - Stable port: keep the port already in config.prop / yaml, do not
#    randomise on every start. Random ports break the manager app and the
#    Clash bridge on every reload.
#  - NO chattr +i locking, NO airplane toggle anywhere in this module.
#  - NO SNI NFQUEUE rules (yaml sni_filter is disabled anyway).
AGH_DIR="/data/adb/agh"
BIN_DIR="$AGH_DIR/bin"
SCRIPT_DIR="$AGH_DIR/scripts"
MAIN_LOG="$AGH_DIR/agh.log"
MODDIR="$(dirname "$0")"

agh_running() {
  for p in /proc/[0-9]*; do
    [ -f "$p/cmdline" ] || continue
    c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
    case "$c" in "$BIN_DIR/AdGuardHome"*) ;;
      *) continue;;
    esac
    if [ -f "$p/comm" ]; then
      comm=$(cat "$p/comm" 2>/dev/null)
      [ "$comm" = "AdGuardHome" ] || continue
    fi
    return 0
  done
  return 1
}

# Load port, unify yaml + config.prop to the same stable port.
. "$SCRIPT_DIR/config.prop" 2>/dev/null
PORT="${redir_port:-59156}"
case "$PORT" in ''|*[!0-9]*) PORT=59156;; esac
sed -i "s/^redir_port=.*/redir_port=$PORT/" "$SCRIPT_DIR/config.prop" 2>/dev/null
sed -i "/^dns:/,/^[^[:space:]]/ s/^\\([[:space:]]*port:\\) [0-9]*/\\1 $PORT/" "$BIN_DIR/AdGuardHome.yaml" 2>/dev/null

# Stop an already-running AGH so the new config is actually used.
# This is the soft-reboot fix: the original skipped initialisation here.
if agh_running; then
  echo "$(date '+%F %T') TempRoot: stopping old AGH for reload" >> "$MAIN_LOG"
  for p in /proc/[0-9]*; do
    [ -f "$p/cmdline" ] || continue
    c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
    case "$c" in "$BIN_DIR/AdGuardHome"*) kill "${p#/proc/}" 2>/dev/null;; esac
  done
  for i in 1 2 3 4 5; do agh_running || break; sleep 1; done
  agh_running && {
    for p in /proc/[0-9]*; do
      [ -f "$p/cmdline" ] || continue
      c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
      case "$c" in "$BIN_DIR/AdGuardHome"*) kill -9 "${p#/proc/}" 2>/dev/null;; esac
    done
    sleep 1
  }
fi

export SSL_CERT_DIR="/system/etc/security/cacerts/"
"$BIN_DIR/AdGuardHome" --no-check-update &
# Fail-open v2 (twoone-3 idea, extended): wait for the DNS port to
# actually listen, up to 120s (AGH_WAIT_TIMEOUT overrides for tests).
# Process alive alone is not enough - a dead filter load or a port
# conflict leaves a process but no listener, and redirecting to it
# is a DNS blackout. Listening check uses /proc/net/tcp hex port.
WAIT="${AGH_WAIT_TIMEOUT:-120}"
HEXPORT=$(printf "%04X" "$PORT")
LISTENING=0
i=0
while [ "$i" -lt "$WAIT" ]; do
  agh_running || break
  if grep -q ":$HEXPORT" /proc/net/tcp 2>/dev/null; then LISTENING=1; break; fi
  sleep 1; i=$((i+1))
done
if [ "$LISTENING" -eq 1 ]; then
  echo "$(date '+%F %T') TempRoot: AGH started on port $PORT" >> "$MAIN_LOG"
  "$SCRIPT_DIR/iptables.sh" &
  "$SCRIPT_DIR/ProxyConfig.sh" &
  "$SCRIPT_DIR/ClashAppBridge.sh" &
else
  echo "$(date '+%F %T') TempRoot: AGH failed to start, iptables NOT applied (fail-open)" >> "$MAIN_LOG"
fi
