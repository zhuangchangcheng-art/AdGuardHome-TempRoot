#!/system/bin/sh
# TempRoot Remake installer - minimal, no destructive steps.
# Magisk/KSU provides: MODPATH (module dir), ZIPFILE (this zip).
# This script does NOT: remove hosts modules, delete old data dirs,
# lock scripts with chattr, rewrite proxy subscriptions, or toggle
# airplane mode. It only backs up the previous yaml/config once and
# installs the new scripts + yaml + filters URLs into /data/adb/agh.
SKIPUNZIP=1
ui_print "- TempRoot Remake: installing (no reboot required for activate.sh)"
AGH_DIR="/data/adb/agh"
BIN_DIR="$AGH_DIR/bin"
SCRIPT_DIR="$AGH_DIR/scripts"
BACKUP_DIR="$AGH_DIR/backup"
mkdir -p "$AGH_DIR" "$BIN_DIR" "$SCRIPT_DIR" "$BACKUP_DIR"
if [ -f "$BIN_DIR/AdGuardHome.yaml" ]; then
  cp -f "$BIN_DIR/AdGuardHome.yaml" "$BACKUP_DIR/AdGuardHome.yaml.bak" 2>/dev/null
  ui_print "- backed up old AdGuardHome.yaml"
fi
if [ -f "$SCRIPT_DIR/config.prop" ]; then
  cp -f "$SCRIPT_DIR/config.prop" "$BACKUP_DIR/config.prop.bak" 2>/dev/null
fi
for file in uninstall.sh module.prop service.sh action.sh activate.sh; do
  unzip -o "$ZIPFILE" "$file" -d "$MODPATH" 2>/dev/null
done
unzip -o "$ZIPFILE" "scripts/*" -d "$AGH_DIR" 2>/dev/null
unzip -o "$ZIPFILE" "bin/*" -d "$AGH_DIR" 2>/dev/null
# The AGH binary itself is NOT in this source repo (see README).
# The flashable zip built locally includes bin/AdGuardHome; if it is
# missing here, installation still succeeds but service.sh will log
# fail-open and will NOT apply iptables rules.
chmod +x "$BIN_DIR/AdGuardHome" 2>/dev/null
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null
echo "temproot-remake-20261031" > "$AGH_DIR/temproot-remake.marker"
# Best-effort auto-start: normally service.sh only runs at boot, and a hard
# reboot would lose temporary root, so try to start now. If the installer
# kills background children, use the manager Action button instead.
if [ -f "$MODPATH/service.sh" ] && [ -f "$BIN_DIR/AdGuardHome" ]; then
  sh "$MODPATH/service.sh" >/dev/null 2>&1 || true
  ui_print "- auto-start attempted; if AGH is not running, tap the module Action button"
fi
ui_print "- Done. Do NOT run the original AdGuardHome module at the same time."
ui_print "- Temporary root: after re-obtaining root, run activate.sh (see README) instead of a hard reboot."
