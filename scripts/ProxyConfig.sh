#!/system/bin/sh
# TempRoot remake: POSIX sh version of the original ProxyConfig.
# Original used bash arrays + herestring (<<<), which fails under dash
# and is fragile under Android mksh. This version uses a plain
# newline-separated list, so `sh -n` passes and the loop is testable.
# Behaviour preserved: only for proxy MODULE configs (box / mihomo /
# clash module), NOT for Clash App (that is ClashAppBridge.sh).
# Never restarts Clash App, never toggles airplane mode.
CONFIG_FILE="$(dirname "$0")/config.prop"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
LOCAL_DNS="127.0.0.1:${redir_port}"

for p in /proc/[0-9]*; do [ "$p" = "/proc/$$" ] && continue; [ -f "$p/cmdline" ] || continue; c=; IFS= read -r c < "$p/cmdline" 2>/dev/null; case "$c" in *"$0"*) exit;; esac; done

PROXY_CONFIGS="/data/adb/box_bll/clash/*.yaml|/data/adb/box_bll/scripts/box.service restart
/data/adb/box/mihomo/*.yaml|/data/adb/box/scripts/box.service restart
/data/clash/*.yaml|/data/clash/scripts/clash.service -k && /data/clash/scripts/clash.service -s
/data/media/0/Android/Clash/*.yaml|/data/adb/modules/Clash/Scripts/Clash.Service stop; /data/adb/modules/Clash/Scripts/Clash.Service start"

ALL_SECTIONS="direct-nameserver: proxy-server-nameserver: nameserver: default-nameserver: [Rr][Uu][Ll][Ee]-[Ss][Ee][Tt] [Gg][Ee][Oo][Ss][Ii][Tt][Ee] "

restart_service() {
    $1
}

is_standard_config() {
    [ -f "$1" ] || return 1
    [ -z "$PROXY_URL" ] || grep -qF "$PROXY_URL" "$1" || return 1
    grep -q "^[[:space:]]*dns:" "$1" && grep -q "^[[:space:]]*enhanced-mode:[[:space:]]*redir-host" "$1" || return 1
    for section in $ALL_SECTIONS; do
        grep -q "^[[:space:]]*['\"]*${section}" "$1" || continue
        section_content=$(sed -n "/^[[:space:]]*['\"]*${section}/,/^[^[:space:]#]/p" "$1")
        has_local_dns=$(echo "$section_content" | grep -c "^[[:space:]]*-[[:space:]]*$LOCAL_DNS")
        other_dns=$(echo "$section_content" | grep "^[[:space:]]*- " | grep -v "^[[:space:]]*- *#" | grep -v "$LOCAL_DNS" | wc -l)
        commented_local_dns=$(echo "$section_content" | grep -c "^[[:space:]]*#.*-[[:space:]]*$LOCAL_DNS")
        [ $commented_local_dns -gt 0 ] && return 1
        [ $has_local_dns -eq 0 ] || [ $other_dns -gt 0 ] && return 1
    done
    return 0
}

clean_config() {
    [ ! -f "$1" ] && return 1
    for section in $ALL_SECTIONS; do
        sed -i "/^[[:space:]]*['\"]*${section}/,/^[^[:space:]]/{/^[[:space:]]*#\{0,1\}[[:space:]]*-[[:space:]]*127\.0\.0\.1:[0-9][0-9]*$/d;s/^\([[:space:]]*\)#[[:space:]]*\(-[[:space:]]*[^#].*\)/\1\2/}" "$1"
    done
}

process_config() {
    is_standard_config "$1" && return 1
    modified=0
    [ -z "$PROXY_URL" ] || grep -qF "$PROXY_URL" "$1" || {
        esc_url=$(printf "%s" "$PROXY_URL" | sed 's/[&|]/\\&/g'); sed -i "/proxy-providers:/,/url:/{s|^\([[:space:]]*\)url:.*|\1url: \"$esc_url\"|}" "$1" && modified=1
    }
    (grep -q "^[[:space:]]*dns:" "$1" && grep -q "^[[:space:]]*enhanced-mode:[[:space:]]*redir-host" "$1") || {
        sed -i '/^[[:space:]]*dns:/,/^[^[:space:]]/s/^\([[:space:]]*enhanced-mode:\).*/\1 redir-host/' "$1" && modified=1
    }
    clean_config "$1"
    for section in $ALL_SECTIONS; do
        sed -i "/^[[:space:]]*['\"]*${section}/,/^[[:space:]]*[^[:space:]#'\"=-]/{/- $LOCAL_DNS/! s/^\\([[:space:]]*\\)\\(-[[:space:]]*[^#].*\\)/\\1# \\2/;/- $LOCAL_DNS/b;/^[[:space:]]*['\"]*${section}/{n;:l;/^[[:space:]]*#*[[:space:]]*-/!{n;bl};/- $LOCAL_DNS/!{s/^\\([[:space:]]*\\)\\(#*[[:space:]]*-[[:space:]]*.*\\)/\\1- $LOCAL_DNS\\
\\1# \\2/}}}" "$1"
    done
    [ $modified -eq 1 ] && return 0
    grep -q "$LOCAL_DNS" "$1"
    return $?
}

while :; do
    . "$CONFIG_FILE" 2>/dev/null
    LOCAL_DNS="127.0.0.1:${redir_port}"
    echo "$PROXY_CONFIGS" | while IFS= read -r line; do
        config_glob="${line%%|*}"
        restart_cmd="${line#*|}"
        need_restart=0
        for config_file in $config_glob; do
            [ ! -f "$config_file" ] && continue
            if [ "$1" = "--clean" ]; then clean_config "$config_file"; continue; fi
            process_config "$config_file"
            [ $? -eq 0 ] && need_restart=1
        done
        [ $need_restart -eq 1 ] && restart_service "$restart_cmd"
    done
    [ "$1" = "--clean" ] && exit 0
    sleep 5
done
