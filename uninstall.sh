#!/system/bin/sh
# TempRoot Remake uninstall: kill daemons, restore proxy configs,
# clear iptables, remove data dir ONLY if it carries our marker.
# This avoids deleting the original module's data if both were installed.
AGH_DIR="/data/adb/agh"
# Graceful first, force after 2s (linjoin order). Do NOT kill by
# substring match: only cmdline prefix AdGuardHome, plus scripts
# daemons by exact script path, to avoid killing the uninstaller itself.
kill_aghs() {
  for p in /proc/[0-9]*; do
    IFS= read -r cmd < "$p/cmdline" 2>/dev/null
    case "$cmd" in
      "$AGH_DIR/bin/AdGuardHome"*) kill "$1" "${p#/proc/}" 2>/dev/null;;
      *"$AGH_DIR/scripts/iptables.sh"*|*"$AGH_DIR/scripts/ProxyConfig.sh"*|*"$AGH_DIR/scripts/ClashAppBridge.sh"*) kill "$1" "${p#/proc/}" 2>/dev/null;;
    esac
  done
}
kill_aghs ""
sleep 2
kill_aghs "-9"
sleep 1
[ -f "$AGH_DIR/scripts/ClashAppBridge.sh" ] && "$AGH_DIR/scripts/ClashAppBridge.sh" --clean 2>/dev/null
[ -f "$AGH_DIR/scripts/ProxyConfig.sh" ] && "$AGH_DIR/scripts/ProxyConfig.sh" --clean 2>/dev/null
iptables -w 2 -t nat -D OUTPUT -j ADGUARD 2>/dev/null
iptables -w 2 -t nat -F ADGUARD 2>/dev/null
iptables -w 2 -t nat -X ADGUARD 2>/dev/null
iptables -w 2 -D OUTPUT -p tcp --dport 853 -j REJECT 2>/dev/null
iptables -w 2 -D OUTPUT -p udp --dport 853 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null
iptables -w 2 -t filter -D OUTPUT -j AGH_SNI 2>/dev/null
iptables -w 2 -t filter -F AGH_SNI 2>/dev/null
iptables -w 2 -t filter -X AGH_SNI 2>/dev/null
ip6tables -w 2 -D OUTPUT -j ADGUARD6 2>/dev/null
ip6tables -w 2 -F ADGUARD6 2>/dev/null
ip6tables -w 2 -X ADGUARD6 2>/dev/null
ip6tables -w 2 -t filter -D OUTPUT -j AGH_SNI 2>/dev/null
ip6tables -w 2 -t filter -F AGH_SNI 2>/dev/null
ip6tables -w 2 -t filter -X AGH_SNI 2>/dev/null
if [ -f "$AGH_DIR/temproot-remake.marker" ]; then
  rm -rf "$AGH_DIR"
fi
