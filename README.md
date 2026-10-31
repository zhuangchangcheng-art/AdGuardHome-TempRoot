# AdGuard Home TempRoot Remake

AdGuard Home on a **temporary-root** phone, rebuilt from several same-origin
modules instead of patching the original. Goal: DNS ad filtering **and**
Muse **and** Clash **and** games at the same time, without the side effects
that made the original unusable for this combination.

## What is different from the original (liuzq2002) module

| Problem in the original | Fix in this remake |
|---|---|
| DNS queries carry the real Chinese carrier subnet (ECS) to upstream, Meta DNS returns a China edge that does not work through the proxy | `edns_client_subnet.enabled: false` in yaml |
| AAAA answers on a network where local IPv6 is broken | `aaaa_disabled: true` |
| Upstream was Tencent DoH only, cache kept bad answers 12 h | Upstream doh.pub + alidns, fallback 223.5.5.5 + doh.pub, optimistic cache 12 h -> 1 h, cache TTL min 600 -> 60 s, max 3600 -> 1800 s, upstream timeout 10 s -> 5 s |
| iptables daemon toggled airplane mode on every rule rebuild, dropping live connections | **No airplane toggle anywhere** (iptables, ProxyConfig, bridge) |
| SNI NFQUEUE queue for TCP 443/8443 | **Removed** (yaml sni_filter was already disabled; the queue only added a packet path that can stall) |
| Port randomised on every cold start, breaking the manager app and the Clash bridge | **Stable port** 59156, unified in yaml + config.prop, never re-rolled |
| Soft reboot: if AGH was already running, service.sh skipped initialisation, so a patched config never took effect | service.sh **stops the old AGH and restarts it** with the current yaml |
| If AGH failed to start, the 53 redirect still pointed at a dead port = whole-phone DNS blackout | **Fail-open** (twoone-3 idea): redirect is only applied while AGH is alive |
| Clash App (not a module) was never bridged, so its DNS bypassed AGH | ClashAppBridge.sh: backs up once, rewrites nameserver/proxy-server-nameserver to AGH, `--clean` restores, never restarts Clash, never touches the subscription URL |
| ProxyConfig used bash arrays + herestring, failing under dash | Rewritten in **POSIX sh**, `sh -n` and `bash -n` both pass for every script |
| NoAdsService loop deleted app ad directories every 5 s, forced private DNS off, locked /data/system/ifw | **Not started by service.sh.** The trimmed file is kept only as an optional extra; the two persistent side effects are removed from it |
| customize.sh did hosts-module checks, chattr locking, old-dir deletion | Minimal installer: back up old yaml/config once, install scripts, nothing destructive |

## Ideas borrowed, with attribution

- **liuzq2002/Adguard-Home-For-Magisk-Mod** (MIT): AGH fork binary, yaml base,
  1282 user rules (anti-fraud fzpt.cn rules kept), filter URLs, ProxyConfig
  concept. This remake is not that project.
- **twoone-3/AdGuardHomeForRoot**: fail-open (skip iptables if the daemon
  is not listening), loop prevention, IPv6 DNS reject, update mechanism idea.
- **Ceromis/AdGuard-Home-for-Android**: proxy compatibility only when a
  supported proxy is actually in use, restore when it stops, separate
  bootstrap DNS from AGH's encrypted upstream.
- **410154425/AdGuardHome_magisk**: mode/config file, private-DNS-must-be-off
  requirement, self-check script idea.
- **linjoin/AdGuardHomeForRoot (AutoOpt)**: root-manager independence
  (Magisk / KSU / APatch) as a design goal.

## What is NOT in this repo

- **The AGH binary** (`bin/AdGuardHome`, ~23 MB, arm64). GitHub file upload
  here only accepts UTF-8 text, so the binary cannot be pushed through this
  tooling. The flashable zip built locally includes it; the source repo
  contains everything else. Filter rule files are also not bundled: AGH
  downloads them on first start from the URLs in the yaml.
- **No claim of phone verification.** VM tests below prove syntax, yaml,
  bridge logic, service reload and fail-open. They do **not** prove
  iptables on a real phone, KSU soft-reboot reload, or the real Clash App
  config path. Those are listed as untested and need the phone log.

## Install (temporary root)

1. Charge to at least 30%. Disable or uninstall the **original**
   AdGuardHome module first - do not run both, they share /data/adb/agh.
2. Flash the local zip (not this repo alone) in your root manager.
3. **Do not hard-reboot.** A hard reboot loses temporary root.
4. Start it without a terminal: the installer tries to start it at install
   time; if it is not running, tap the module's **Action** button in your
   root manager (action.sh runs service.sh, then opens the Web UI).
   MT / terminal fallback, only if Action does not work:
   `su -c sh /data/adb/modules/AdGuardHomeTempRoot/activate.sh`
5. Check in order: a normal game / long connection first, then Muse,
   then Clash with system proxy still on, then filtering.
   Logs: `/data/adb/agh/agh.log` and `/data/adb/agh/clash-app-bridge.log`.
   If the bridge log says "no config found", it did nothing - send that
   log back so the real Clash App path can be added.

## Uninstall

Uninstalling the module runs uninstall.sh: it kills AGH and the daemons,
restores bridged proxy configs, clears ADGUARD / ADGUARD6 / AGH_SNI chains,
and removes /data/adb/agh only if it carries the remake marker file.

## VM tests run before publishing (2026-10-31)

- `sh -n` + `bash -n` pass for all 10 scripts (ProxyConfig previously
  failed `sh -n`).
- yaml parses, port 59156, ECS off, AAAA on, optimistic 1 h, upstreams
  doh.pub + alidns.
- Service test with a compiled stub AGH + stub iptables: AGH starts on
  stable port 59156, iptables rules are applied, no `settings`
  (airplane) call, no SNI call. All PASS on the final run.
- Second service run replaces the old AGH PID (soft-reboot reload).
- Fail-open test: with the AGH binary removed, service logs
  "fail-open" and applies **no** REDIRECT rule.
- Two real bugs found and fixed by this testing, not by code review:
  1. `IFS= read -r c < /proc/.../cmdline || continue` always discards
     the value: read returns 1 on EOF (cmdline has no trailing newline)
     even when it populated the variable. The original scripts avoided
     this by not using `|| continue`; this remake now does the same
     and guards the race with `[ -f "$p/cmdline" ] || continue`.
  2. Detection must be by argv0 prefix, not by "contains": a contains
     match kills any process whose command line merely mentions the
     path (including the test harness itself). Reverted to prefix.
  3. config.prop still carried a stale random port (31587) while yaml
     had 59156. Now both are 59156, unified by service.sh on start.
- ClashAppBridge sample test: bridge / idempotent / restore pass on a
  sample Clash yaml (from the previous v6 test, same script).

## Known untested items (phone needed)

- Real iptables / KSU soft-reboot reload.
- Real Clash App config path (bridge is no-op if the path is not found).
- Real ECS edge behaviour on the user's actual carrier network.
- NoAdsService is not started; app splash-ad directory blocking is
  therefore not part of this remake by default.
