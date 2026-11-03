#!/bin/bash
# ASCS 免费 IPv6 容器一键建节点
# 架构: 客户端 --VLESS+WS+TLS--> Cloudflare --隧道--> cloudflared --> Xray(127.0.0.1) --> 互联网(WARP 出站 IPv4)
#       客户端 --Hysteria2(UDP/QUIC)--> 服务器 IPv6:443 --> Xray --> 互联网
#
# 用法(在服务器上以 root 执行):  bash setup.sh
# 密钥全部在服务器本地随机生成，保存在 /etc/proxy/env (权限 600)，不会离开服务器。
# 所有下载均带 SHA256 校验，任一不匹配即中止。
#
# 依据: https://szb123.com/files/ascs-free-proxy-node-skill.md (原文件脚本多处乱码，此为重写干净版)

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "请用 root 运行: sudo -i 后再执行"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
MIRROR="https://gh.llkk.cc/https://github.com"
D=/etc/proxy

echo "==> [1/8] 安装系统依赖"
apt-get update -qq
apt-get install -y -qq unzip openssl python3 ca-certificates curl iproute2 >/dev/null
echo "依赖 OK"

echo "==> [2/8] 下载组件(经 GitHub 镜像，逐个 SHA256 校验)"
cd /tmp
dl() { # $1=本地文件名 $2=下载地址 $3=期望 SHA256
  curl -fsSL --retry 3 -o "$1" "$2"
  echo "$3  $1" | sha256sum -c --quiet && echo "校验通过: $1"
}
dl Xray.zip    "$MIRROR/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip" \
  23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
dl hysteria    "$MIRROR/apernet/hysteria/releases/download/app/v2.13.0/hysteria-linux-amd64" \
  907ba8c9693edb104b20582681fb7dc15639d5b64a9cbb616a7b539190a86691
dl wgcf        "$MIRROR/ViRb3/wgcf/releases/download/v2.3.1/wgcf_2.3.1_linux_amd64" \
  4fb7a136aa470ece11d17949c7db07b040ec9c604742dc8680bcf1889f85d0c8
dl cloudflared "$MIRROR/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-linux-amd64" \
  d33ff2d14475178d2012c2c56beba87389ac5ded27649519f198a7d3134a99db

unzip -o -q Xray.zip xray -d /usr/local/bin
install -m755 hysteria    /usr/local/bin/hysteria
install -m755 wgcf        /usr/local/bin/wgcf
install -m755 cloudflared /usr/local/bin/cloudflared
echo "组件安装 OK"

echo "==> [3/8] 生成本地密钥 (/etc/proxy/env, 权限 600)"
mkdir -p "$D/warp" /var/www/sub
chmod 700 "$D"
if [ ! -f "$D/env" ]; then
  cat > "$D/env" <<EOF
U=$(cat /proc/sys/kernel/random/uuid)
P=$(openssl rand -hex 8)
H=$(openssl rand -hex 16)
S=$(openssl rand -hex 8)
EOF
  chmod 600 "$D/env"
  echo "已生成新密钥"
else
  echo "沿用已有密钥 ($D/env)"
fi
# shellcheck disable=SC1091
. "$D/env"

echo "==> [4/8] 获取本机公网 IPv6"
IP6=$(ip -6 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1 || true)
[ -n "$IP6" ] || { echo "未找到公网 IPv6，请检查网络后重试"; exit 1; }
echo "IP6=$IP6" > "$D/ip6"
echo "公网 IPv6: $IP6"

echo "==> [5/8] 注册 WARP(为 IPv4 站点提供出站；失败则跳过)"
if ( cd "$D/warp" && { [ -f wgcf-account.toml ] || wgcf register --accept-tos >/dev/null 2>&1; } \
     && wgcf generate >/dev/null 2>&1 ); then
  echo "WARP_OK"
else
  echo "WARP_FAIL(继续安装；IPv4-only 站点将不可达，可稍后手动重试)"
fi

echo "==> [6/8] 生成 Hysteria2 自签证书"
if [ ! -f "$D/hy.key" ]; then
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout "$D/hy.key" -out "$D/hy.crt" -subj "/CN=www.bing.com" 2>/dev/null
  chmod 600 "$D/hy.key"
fi
echo "证书 OK"

echo "==> [7/8] 生成 Xray / Hysteria2 配置与订阅文件"
cat > "$D/gen.py" <<'PYEOF'
import json, os, re, base64, urllib.parse

D = "/etc/proxy"
env = dict(l.strip().split("=", 1) for l in open(D + "/env") if "=" in l)
ip6 = open(D + "/ip6").read().strip().split("=", 1)[1]
U, P, H, S = env["U"], env["P"], env["H"], env["S"]

direct = {"tag": "direct", "protocol": "freedom",
          "settings": {"domainStrategy": "ForceIPv6"}}
outbounds = [direct]
rules = [{"ip": ["::/0"], "outboundTag": "direct"}]

prof = D + "/warp/wgcf-profile.conf"
if os.path.exists(prof):
    t = open(prof).read()
    key = re.search(r"PrivateKey\s*=\s*(\S+)", t).group(1)
    pub = re.search(r"PublicKey\s*=\s*(\S+)", t).group(1)
    addrs = [a.strip() for l in re.findall(r"Address\s*=\s*(.+)", t)
             for a in l.split(",")]
    outbounds.append({"tag": "warp", "protocol": "wireguard", "settings": {
        "secretKey": key, "address": addrs, "mtu": 1280,
        "domainStrategy": "ForceIPv4",
        "peers": [{"publicKey": pub,
                   "endpoint": "[2606:4700:d0::a29f:c001]:2408",
                   "allowedIPs": ["0.0.0.0/0", "::/0"]}]}})
    rules.append({"ip": ["0.0.0.0/0"], "outboundTag": "warp"})

cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {"tag": "front", "listen": "127.0.0.1", "port": 10086,
         "protocol": "vless",
         "settings": {"clients": [], "decryption": "none",
                      "fallbacks": [{"path": "/" + P, "dest": 10085},
                                    {"dest": 10087}]},
         "streamSettings": {"network": "raw", "security": "none"}},
        {"tag": "ws", "listen": "127.0.0.1", "port": 10085,
         "protocol": "vless",
         "settings": {"clients": [{"id": U}], "decryption": "none"},
         "streamSettings": {"network": "ws", "wsSettings": {"path": "/" + P}},
         "sniffing": {"enabled": True,
                      "destOverride": ["http", "tls", "quic"],
                      "routeOnly": True}},
        {"tag": "socks-in", "listen": "127.0.0.1", "port": 10808,
         "protocol": "socks", "settings": {"udp": True},
         "sniffing": {"enabled": True,
                      "destOverride": ["http", "tls", "quic"],
                      "routeOnly": True}},
    ],
    "outbounds": outbounds,
    "routing": {"domainStrategy": "IPIfNonMatch", "rules": rules},
}
json.dump(cfg, open(D + "/xray.json", "w"), indent=1)

open(D + "/hy.yaml", "w").write(
    "listen: :443\n"
    "tls:\n"
    f"  cert: {D}/hy.crt\n"
    f"  key: {D}/hy.key\n"
    "auth:\n"
    "  type: password\n"
    f"  password: {H}\n"
    "masquerade:\n"
    "  type: proxy\n"
    "  proxy:\n"
    "    url: https://www.bing.com/\n"
    "    rewriteHost: true\n"
    "outbounds:\n"
    "  - name: xr\n"
    "    type: socks5\n"
    "    socks5:\n"
    "      addr: 127.0.0.1:10808\n")

host = open(D + "/host").read().strip() if os.path.exists(D + "/host") else ""
lines = []
if host:
    q = urllib.parse.urlencode({"encryption": "none", "security": "tls",
                                "sni": host, "fp": "chrome", "type": "ws",
                                "host": host, "path": "/" + P})
    lines.append(f"vless://{U}@{host}:443?{q}#ASCS-VLESS-CF")
lines.append(f"hysteria2://{H}@[{ip6}]:443"
             f"?sni=www.bing.com&insecure=1#ASCS-HY2")

os.makedirs(f"/var/www/sub/{S}", exist_ok=True)
open("/var/www/sub/index.html", "w").write("")
open(f"/var/www/sub/{S}/index.html", "w").write("")
open(f"/var/www/sub/{S}/sub", "w").write(
    base64.b64encode("\n".join(lines).encode()).decode())
print("SUB_PATH=/" + S + "/sub HOST=" + (host or "none"))
PYEOF
python3 "$D/gen.py"
/usr/local/bin/xray run -test -c "$D/xray.json" >/dev/null && echo "XRAY_CONFIG_OK"

echo "==> [8/8] 写入 systemd 服务并启动"
cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray proxy (VLESS front + WS + SOCKS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -c /etc/proxy/xray.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/hysteria.service <<'EOF'
[Unit]
Description=Hysteria2 server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/proxy/hy.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/subweb.service <<'EOF'
[Unit]
Description=Subscription file server (127.0.0.1:10087)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server 10087 --directory /var/www/sub --bind 127.0.0.1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/cfquick.service <<'EOF'
[Unit]
Description=Cloudflared quick tunnel to Xray front (temporary, IPv6 edge)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --edge-ip-version 6 --url http://127.0.0.1:10086
StandardOutput=append:/var/log/cft.log
StandardError=append:/var/log/cft.log
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 从 cloudflared 日志抓取临时隧道域名，写入 /etc/proxy/host 并重新生成订阅
cat > "$D/qthost.sh" <<'EOF'
#!/bin/bash
L=/var/log/cft.log
for i in $(seq 1 60); do
  h=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$L" 2>/dev/null \
      | head -1 | sed 's#https://##')
  if [ -n "$h" ]; then
    echo "$h" > /etc/proxy/host
    python3 /etc/proxy/gen.py
    echo "TUNNEL_HOST=$h"
    exit 0
  fi
  sleep 2
done
echo "未抓到隧道域名，请检查: journalctl -u cfquick --no-pager | tail -30"
exit 1
EOF
chmod 755 "$D/qthost.sh"

systemctl daemon-reload
systemctl enable --now xray hysteria subweb >/dev/null
# 已配置固定域名隧道(cfnamed)时不再启用临时隧道
if systemctl is-enabled cfnamed >/dev/null 2>&1; then
  systemctl restart xray hysteria
else
  systemctl enable --now cfquick >/dev/null
fi

echo "等待服务就绪..."
sleep 5
for s in xray hysteria subweb cfquick cfnamed; do
  echo "$s: $(systemctl is-active $s 2>/dev/null)"
done
ss -lnt 2>/dev/null | grep -E '1008[578]|:443 ' | awk '{print $1, $5}' || true

if ! systemctl is-enabled cfnamed >/dev/null 2>&1; then
  echo "抓取临时隧道域名..."
  : > /var/log/cft.log
  systemctl restart cfquick
  bash "$D/qthost.sh"
fi

echo "==> 本机自检"
. "$D/env"; . "$D/ip6"
cat > /tmp/hyc.yaml <<EOF
server: [$IP6]:443
auth: $H
tls:
  sni: www.bing.com
  insecure: true
socks5:
  listen: 127.0.0.1:1081
EOF
/usr/local/bin/hysteria client -c /tmp/hyc.yaml >/tmp/hyc.log 2>&1 &
HP=$!; sleep 4
echo "HY2_TEST google: $(curl -s -m 15 -o /dev/null -w '%{http_code}' -x socks5h://127.0.0.1:1081 https://www.google.com/generate_204)"
kill $HP 2>/dev/null; rm -f /tmp/hyc.yaml
echo "VIA_XRAY github: $(curl -s -m 15 -o /dev/null -w '%{http_code}' -x socks5h://127.0.0.1:10808 https://github.com)"

echo "================== 完成 =================="
echo "SUB_URL=https://$(cat $D/host 2>/dev/null)/$S/sub"
echo "把上面的 SUB_URL 作为订阅添加到客户端(Shadowrocket / v2rayN / v2rayNG / NekoBox)，"
echo "更新后会出现 ASCS-VLESS-CF 和 ASCS-HY2 两个节点。"
echo "注意: 临时隧道域名每次重启会变；要固定域名请看 README.md 第 3 步。"
echo DONE
