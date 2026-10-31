#!/system/bin/sh
# TempRoot Remake uninstall: kill daemons, restore proxy configs,
# clear iptables, remove data dir ONLY if it carries our marker.
# This avoids deleting the original module's data if both were installed.
AGH_DIR="/data/adb/agh"
while true; do
  found=0
  for p in /proc/[0-9]*; do
    IFS= read -r cmd < "$p/cmdline" 2>/dev/null
    case "$cmd" in
      "$AGH_DIR/bin/AdGuardHome"*|*"$AGH_DIR/scripts/"*)
        kill -9 "${p#/proc/}" 2>/dev/null; found=1;;
    esac
  done
  [ "$found" -eq 0 ] && break
  sleep 1
done
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
