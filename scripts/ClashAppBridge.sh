#!/system/bin/sh
# Clash App DNS bridge v2 - fixes from 12-module research
# Business DNS only to AGH: nameserver, fallback, direct-nameserver,
# nameserver-policy. Bootstraps NEVER to AGH: default-nameserver and
# proxy-server-nameserver keep independent IPs, otherwise node domain
# resolution depends on AGH and AGH upstream may depend on proxy -> loop.
# If a previous v1 bridge put AGH into proxy-server, restore from
# backup first, then re-bridge correctly.
# If no candidate profile exists, log "no config found" instead of
# silently doing nothing. --once for VM testing, --clean for uninstall.
# Never restarts Clash, never toggles airplane mode, never touches
# proxy-providers / subscription URLs.
AGH_DIR="/data/adb/agh"
CONFIG_FILE="$AGH_DIR/scripts/config.prop"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
LOCAL_DNS="127.0.0.1:${redir_port:-59156}"
LOG="$AGH_DIR/clash-app-bridge.log"
BACKUP_DIR="$AGH_DIR/backup/clash-app"
for p in /proc/[0-9]*; do
  [ "$p" = "/proc/$$" ] && continue
  [ -f "$p/cmdline" ] || continue
  c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
  case "$c" in *"$0"*)
    case "$1" in --clean|--once) ;; *) exit 0;; esac
  esac
done
in_section() {
  # $1=file $2=section name, return 0 if AGH present in that section
  awk -v want="$2" '
    /^ *[a-zA-Z_-]+:/ {
      if ($0 ~ ("^ *" want ":")) sec=1; else sec=0
      next
    }
    sec==1 && /127\.0\.0\.1:/ { found=1 }
    END { exit !found }
  ' "$1"
}
bridge_one() {
  f="$1"
  [ -f "$f" ] || return 0
  grep -q "^[[:space:]]*dns:" "$f" || return 0
  mkdir -p "$BACKUP_DIR"
  bak="$BACKUP_DIR/$(echo "$f" | tr '/' '_').bak"
  [ -f "$bak" ] || cp -f "$f" "$bak"
  if in_section "$f" "proxy-server-nameserver"; then
    cp -f "$bak" "$f"
    echo "$(date '+%F %T') restored v1-buggy proxy-server bridge, re-bridging correctly: $f" >> "$LOG"
  fi
  if in_section "$f" "nameserver"; then echo "$(date '+%F %T') already bridged $f" >> "$LOG"; return 0; fi
  # Inline-list form (e.g. nameserver: [223.5.5.5, 119.29.29.29]) -> AGH only, bootstraps untouched
  sed -i -E "s|^([[:space:]]*nameserver:[[:space:]]*)\[.*\]|\1[127.0.0.1:${redir_port:-59156}]|" "$f" 2>/dev/null
  sed -i -E "s|^([[:space:]]*fallback:[[:space:]]*)\[.*\]|\1[127.0.0.1:${redir_port:-59156}]|" "$f" 2>/dev/null
  # If nameserver/fallback are now inline AGH-only, log and return (awk section logic not needed)
  if grep -q "^[[:space:]]*nameserver:[[:space:]]*\[127.0.0.1:" "$f"; then echo "$(date '+%F %T') bridged $f (backup $bak, business DNS only, bootstraps untouched)" >> "$LOG"; return 0; fi
  tmp="$f.agh-bridge-tmp"
  awk -v dns="$LOCAL_DNS" '
    /^ *[a-zA-Z_-]+:/ && !/^-/ {
      if ($0 ~ /^ *nameserver:/) sec="target"
      else if ($0 ~ /^ *fallback:/) sec="target"
      else if ($0 ~ /^ *direct-nameserver:/) sec="target"
      else if ($0 ~ /^ *nameserver-policy:/) sec="target"
      else sec="other"
      print $0
      if (sec=="target") print "    - " dns
      next
    }
    sec=="target" && /^ *- / { print "# " $0; next }
    sec=="target" && /^ *$/ { print $0; next }
    { sec="other"; print $0 }
  ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
  echo "$(date '+%F %T') bridged $f (backup $bak, business DNS only, bootstraps untouched)" >> "$LOG"
}
clean_one() {
  f="$1"
  bak="$BACKUP_DIR/$(echo "$f" | tr '/' '_').bak"
  [ -f "$bak" ] && [ -f "$f" ] && cp -f "$bak" "$f" && rm -f "$bak" && \
    echo "$(date '+%F %T') restored $f" >> "$LOG"
}
run_once() {
  found=0
  for pat in \
    "/data/data/com.github.metacubex.clash.meta/files/imported/*/config.yaml" \
    "/data/data/com.github.metacubex.clash.meta/files/processing/config.yaml" \
    "/data/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
    "/data/data/com.github.metacubex.clash.meta/files/*.yaml" \
    "/data/media/0/Android/data/com.github.metacubex.clash.meta/files/profiles/*.yaml" \
    "/data/data/com.github.kr328.clash/files/*.yaml" \
    "/data/media/0/Android/Clash/*.yaml" ; do
    for f in $pat; do
      [ -f "$f" ] || continue
      found=1
      if [ "$1" = "--clean" ]; then clean_one "$f"; else bridge_one "$f"; fi
    done
  done
  if [ "$found" -eq 0 ] && [ "$1" != "--clean" ]; then
    echo "$(date '+%F %T') no config found: Clash App profile not in candidate paths, bridge idle" >> "$LOG"
  fi
}
if [ "$1" = "--clean" ]; then run_once --clean; exit 0; fi
if [ "$1" = "--once" ]; then run_once; exit 0; fi
run_once
while :; do
  . "$CONFIG_FILE" 2>/dev/null
  LOCAL_DNS="127.0.0.1:${redir_port:-59156}"
  run_once
  sleep 30
done
