#!/system/bin/sh
# Manual activation for temporary root: run after re-obtaining root,
# without a hard reboot (which would lose temporary root again).
# Usage (in a root terminal, e.g. MT Manager):
#   su -c sh /data/adb/modules/AdGuardHomeTempRoot/activate.sh
# service.sh lives in the module directory; its data scripts live in
# /data/adb/agh/scripts (installed by customize.sh).
MODDIR="$(dirname "$0")"
sh "$MODDIR/service.sh"
