#!/system/bin/sh
# Clash App DNS bridge (AGH comprehensive fix, v6)
# Purpose: when a Clash *app* (not a proxy module) is in use, its own
# resolver would otherwise bypass AGH entirely when system proxy is on.
# This script only rewrites the app profile's nameserver lists to put
# AGH first, so proxied and direct paths get the same ECS-off answer.
# Safety rules, all deliberate:
#  - only touches files that actually exist from the candidate list;
#    if none exist it does nothing and logs nothing;
#  - backs up the original once, never overwrites an existing backup;
#  - never restarts Clash, never toggles airplane mode, never touches
#    proxy-providers / subscription URLs;
#  - --clean restores from backup and exits (used on uninstall).
AGH_DIR="/data/adb/agh"
CONFIG_FILE="$AGH_DIR/scripts/config.prop"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
LOCAL_DNS="127.0.0.1:${redir_port}"
LOG="$AGH_DIR/clash-app-bridge.log"
BACKUP_DIR="$AGH_DIR/backup/clash-app"

# single-instance guard (same style as the other daemons)
for p in /proc/[0-9]*; do
  [ "$p" = "/proc/$$" ] && continue
  [ -f "$p/cmdline" ] || continue
  c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
  case "$c" in *"$0"*) exit 0;; esac
done

bridge_one() {
  f="$1"
  [ -f "$f" ] || return 0
  grep -q "^[[:space:]]*dns:" "$f" || return 0
  # already bridged: AGH address already present anywhere in the file
  grep -qF "$LOCAL_DNS" "$f" && return 0
  mkdir -p "$BACKUP_DIR"
  bak="$BACKUP_DIR/$(echo "$f" | tr '/' '_').bak"
  [ -f "$bak" ] || cp -f "$f" "$bak"
  tmp="$f.agh-bridge-tmp"
  # awk: after a nameserver: / proxy-server-nameserver: header, insert
  # AGH first and comment out the other list entries in that section.
  awk -v dns="$LOCAL_DNS" '
    /^ *[a-zA-Z_-]+:/ && !/^-/ {
      if ($0 ~ /^ *nameserver:/ || $0 ~ /^ *proxy-server-nameserver:/) {
        print $0
        print "    - " dns
        insec = 1
        next
      }
      insec = 0
      print $0
      next
    }
    insec == 1 && /^ *- / {
      print "# " $0
      next
    }
    insec == 1 && /^ *$/ { print $0; next }
    { insec = 0; print $0 }
  ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
  echo "$(date '+%F %T') bridged $f (backup $bak)" >> "$LOG"
}

clean_one() {
  f="$1"
  bak="$BACKUP_DIR/$(echo "$f" | tr '/' '_').bak"
  [ -f "$bak" ] && [ -f "$f" ] && cp -f "$bak" "$f" && rm -f "$bak" && \
    echo "$(date '+%F %T') restored $f" >> "$LOG"
}

# Candidate Clash app profile locations. Glob that matches nothing is
# skipped by the -f test inside bridge_one / clean_one.
for pat in \
  "/data/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
  "/data/data/com.github.metacubex.clash.meta/files/*.yaml" \
  "/data/media/0/Android/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
  "/data/data/com.github.kr328.clash/files/*.yaml" \
  "/data/media/0/Android/Clash/*.yaml" ; do
  for f in $pat; do
    if [ "$1" = "--clean" ]; then clean_one "$f"; else bridge_one "$f"; fi
  done
done

[ "$1" = "--clean" ] && exit 0

while :; do
  . "$CONFIG_FILE" 2>/dev/null
  LOCAL_DNS="127.0.0.1:${redir_port}"
  for pat in \
    "/data/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
    "/data/data/com.github.metacubex.clash.meta/files/*.yaml" \
    "/data/media/0/Android/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
    "/data/data/com.github.kr328.clash/files/*.yaml" \
    "/data/media/0/Android/Clash/*.yaml" ; do
    for f in $pat; do bridge_one "$f"; done
  done
  sleep 30
done
