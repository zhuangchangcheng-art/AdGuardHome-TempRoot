#!/system/bin/sh
# KSU Hot Install entry point (kernelsu.org/guide/module.html)
# KSU replaces /data/adb/modules/<id> with the new version, then runs
# this script the same way as boot scripts: cwd = script dir, stdin
# /dev/null, SIGPIPE ignored, background children are NOT killed when
# the installer exits. That is the official guarantee that customize.sh
# direct backgrounding does NOT have.
# This script must: stop the old AGH (comm + cmdline check, never
# pkill -f), then start service.sh via nohup/setsid, and log the
# outcome. If service.sh itself fails to listen, it will fail-open
# and NOT apply iptables, so a failed hot install cannot black out DNS.
MODDIR="$(dirname "$0")"
AGH_DIR="/data/adb/agh"
LOG="$AGH_DIR/agh.log"
# service.sh lives in the module dir after hot install; fall back to
# the installed copy in /data/adb/agh/scripts if needed.
SERVICE=""
if [ -f "$MODDIR/service.sh" ]; then SERVICE="$MODDIR/service.sh"
elif [ -f "$AGH_DIR/scripts/service.sh" ]; then SERVICE="$AGH_DIR/scripts/service.sh"
fi
echo "$(date '+%F %T') HotInstall: starting, service=$SERVICE" >> "$LOG" 2>/dev/null
if [ -z "$SERVICE" ]; then
  echo "$(date '+%F %T') HotInstall: service.sh not found, use Action as fallback" >> "$LOG" 2>/dev/null
  exit 0
fi
# Stop old AGH gracefully, then force after 5s, comm-checked.
for p in /proc/[0-9]*; do
  [ -f "$p/cmdline" ] || continue
  c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
  case "$c" in "$AGH_DIR/bin/AdGuardHome"*) kill "${p#/proc/}" 2>/dev/null;; esac
done
sleep 2
for p in /proc/[0-9]*; do
  [ -f "$p/cmdline" ] || continue
  c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
  case "$c" in "$AGH_DIR/bin/AdGuardHome"*) kill -9 "${p#/proc/}" 2>/dev/null;; esac
done
# Daemonize service.sh so it survives installer exit.
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$SERVICE" >> "$LOG" 2>&1 &
else
  nohup sh "$SERVICE" >> "$LOG" 2>&1 &
fi
echo "$(date '+%F %T') HotInstall: service launched in background, check agh.log for listening result" >> "$LOG" 2>/dev/null
exit 0
