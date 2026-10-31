#!/system/bin/sh
# TempRoot remake action: start AGH without MT / terminal.
# In Magisk / KSU, tap the module's Action button in the manager.
# This runs service.sh (same as activate.sh), then opens the Web UI.
# No hard reboot, no soft reboot, no terminal needed.
AGH_DIR="/data/adb/agh"
BIN_DIR="$AGH_DIR/bin"
YAML_FILE="$BIN_DIR/AdGuardHome.yaml"

SERVICE=""
if [ -n "$MODDIR" ] && [ -f "$MODDIR/service.sh" ]; then
  SERVICE="$MODDIR/service.sh"
elif [ -f "/data/adb/modules/AdGuardHomeTempRoot/service.sh" ]; then
  SERVICE="/data/adb/modules/AdGuardHomeTempRoot/service.sh"
elif [ -f "/data/adb/modules_update/AdGuardHomeTempRoot/service.sh" ]; then
  SERVICE="/data/adb/modules_update/AdGuardHomeTempRoot/service.sh"
fi

if [ -n "$SERVICE" ]; then
  echo "Starting AdGuard Home..."
  sh "$SERVICE"
  sleep 1
else
  echo "service.sh not found, AGH not started."
fi

PORT=$(sed -n 's/^[[:space:]]*address: 127\.0\.0\.1:\([0-9]*\).*/\1/p' "$YAML_FILE" | head -1)
if [ -n "$PORT" ]; then
  echo "Opening Web UI (port $PORT)..."
  am start -a android.intent.action.VIEW -d "http://127.0.0.1:$PORT" 2>/dev/null
else
  echo "Web UI port not found in yaml, check /data/adb/agh/agh.log"
fi
