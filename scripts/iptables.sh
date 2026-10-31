#!/system/bin/sh
# TempRoot iptables daemon: NAT 53 -> AGH, reject DoT 853, reject IPv6 53.
# Deliberately NO SNI NFQUEUE and NO airplane toggle anywhere.
# SNI filtering is disabled in yaml anyway; queueing TCP 443 only adds
# latency and a packet path that can stall. Airplane toggling drops
# every live connection (games, Muse streams, downloads) and is never
# an acceptable side effect of a DNS rule rebuild.
AGH_DIR="/data/adb/agh"
. "$AGH_DIR/scripts/config.prop"
MAIN_LOG="$AGH_DIR/agh.log"

for p in /proc/[0-9]*; do [ "$p" = "/proc/$$" ] && continue; [ -f "$p/cmdline" ] || continue; c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null; case "$c" in *"$0"*) exit 0;; esac; done

agh_running() {
  for p in /proc/[0-9]*; do
    [ -f "$p/cmdline" ] || continue
    c=""; IFS= read -r c < "$p/cmdline" 2>/dev/null
    case "$c" in "$AGH_DIR/bin/AdGuardHome"*) return 0;; esac
  done
  return 1
}

rebuild_rules() {
  iptables -w 2 -t nat -L ADGUARD 2>/dev/null || {
    iptables -w 2 -t nat -N ADGUARD
    iptables -w 2 -t nat -I OUTPUT -j ADGUARD
  }
  iptables -w 2 -t nat -F ADGUARD
  iptables -w 2 -t nat -A ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port"
  iptables -w 2 -t nat -A ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port"
  iptables -w 2 -A OUTPUT -p tcp --dport 853 -j REJECT 2>/dev/null
  iptables -w 2 -A OUTPUT -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null
  ip6tables -w 2 -L ADGUARD6 2>/dev/null || {
    ip6tables -w 2 -N ADGUARD6
    ip6tables -w 2 -I OUTPUT -j ADGUARD6
  }
  ip6tables -w 2 -F ADGUARD6
  ip6tables -w 2 -A ADGUARD6 -p tcp --dport 853 -j REJECT 2>/dev/null
  ip6tables -w 2 -A ADGUARD6 -p udp --dport 853 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null
  ip6tables -w 2 -A ADGUARD6 -p tcp --dport 53 -j REJECT 2>/dev/null
  ip6tables -w 2 -A ADGUARD6 -p udp --dport 53 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null
  echo "$(date '+%F %T') TempRoot: iptables rules rebuilt, no airplane toggle, no SNI queue" >> "$MAIN_LOG"
}

while true; do
  . "$AGH_DIR/scripts/config.prop" 2>/dev/null
  need_fix=0
  agh_running || {
    export SSL_CERT_DIR="/system/etc/security/cacerts/"
    "$AGH_DIR/bin/AdGuardHome" --no-check-update &
    sleep 2
  }
  # Only apply / rebuild the redirect while AGH is alive (fail-open).
  agh_running || { sleep 5; continue; }
  iptables -w 2 -t nat -C ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null || need_fix=1
  iptables -w 2 -t nat -C ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null || need_fix=1
  iptables -w 2 -C OUTPUT -p tcp --dport 853 -j REJECT 2>/dev/null || need_fix=1
  iptables -w 2 -C OUTPUT -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || need_fix=1
  [ $need_fix -eq 1 ] && rebuild_rules
  sleep 10
done &
