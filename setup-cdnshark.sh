#!/bin/bash
# CDNShark 免费 VPS 个人节点一键部署（仅个人自用）
# 架构: 客户端 --VLESS+Reality(TCP 443)--> Xray --> 直连互联网
#       客户端 --Hysteria2(UDP 443)--> Hysteria --> 直连互联网
# 服务器: 公网 IPv4 直连，无需隧道、无需 WARP。
#
# 用法(在服务器上以 root 执行):  bash setup-cdnshark.sh
# 密钥全部在服务器本地随机生成，保存在 /etc/proxy/env (权限 600)，不会离开服务器。
# 所有下载均带 SHA256 校验，任一不匹配即中止。

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "请用 root 运行: sudo -i 后再执行"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
D=/etc/proxy

echo "==> [1/6] 安装系统依赖"
apt-get update -qq
apt-get install -y -qq unzip openssl python3 ca-certificates curl iproute2 >/dev/null
echo "依赖 OK"

echo "==> [2/6] 下载组件(GitHub 官方源，逐个 SHA256 校验)"
cd /tmp
dl() { # $1=本地文件名 $2=下载地址 $3=期望 SHA256
  curl -fsSL --retry 3 -o "$1" "$2"
  echo "$3  $1" | sha256sum -c --quiet && echo "校验通过: $1"
}
dl Xray.zip    "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip" \
  23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
dl hysteria    "https://github.com/apernet/hysteria/releases/download/app/v2.13.0/hysteria-linux-amd64" \
  907ba8c9693edb104b20582681fb7dc15639d5b64a9cbb616a7b539190a86691

unzip -o -q Xray.zip xray -d /usr/local/bin
install -m755 hysteria /usr/local/bin/hysteria
echo "组件安装 OK"

echo "==> [3/6] 生成本地密钥 (/etc/proxy/env, 权限 600)"
mkdir -p "$D"
chmod 700 "$D"
if [ ! -f "$D/env" ]; then
  cat > "$D/env" <<EOF
U=$(cat /proc/sys/kernel/random/uuid)
P=$(openssl rand -hex 8)
SID=$(openssl rand -hex 4)
EOF
  chmod 600 "$D/env"
  echo "已生成新密钥"
else
  echo "沿用已有密钥 ($D/env)"
fi
# shellcheck disable=SC1091
. "$D/env"

echo "==> [4/6] 生成 Reality 密钥对 + Hysteria2 自签证书"
if [ ! -f "$D/reality.priv" ]; then
  /usr/local/bin/xray x25519 > "$D/reality.keys"
  grep -i "private" "$D/reality.keys" | awk '{print $NF}' > "$D/reality.priv"
  grep -i "public"  "$D/reality.keys" | awk '{print $NF}' > "$D/reality.pub"
  chmod 600 "$D/reality.priv" "$D/reality.pub"
fi
if [ ! -f "$D/hy.key" ]; then
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout "$D/hy.key" -out "$D/hy.crt" -subj "/CN=www.bing.com" 2>/dev/null
  chmod 600 "$D/hy.key"
fi
echo "密钥 OK"

echo "==> [5/6] 获取本机公网 IPv4"
IP4=$(curl -fsS -m 10 https://api.ipify.org || true)
[ -n "$IP4" ] || { echo "未获取到公网 IPv4，请检查网络后重试"; exit 1; }
echo "IP4=$IP4" > "$D/ip4"
echo "公网 IPv4: $IP4"

echo "==> [6/6] 生成 Xray / Hysteria2 配置"
PRIV=$(cat "$D/reality.priv")
PUB=$(cat "$D/reality.pub")
cat > "$D/xray.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "vless-reality", "listen": "0.0.0.0", "port": 443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$U", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "dest": "www.microsoft.com:443",
          "xver": 0, "serverNames": ["www.microsoft.com"],
          "privateKey": "$PRIV", "shortIds": ["$SID"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}
    },
    {
      "tag": "socks-in", "listen": "127.0.0.1", "port": 10808,
      "protocol": "socks", "settings": {"udp": true},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}
    }
  ],
  "outbounds": [{"tag": "direct", "protocol": "freedom"}]
}
EOF
/usr/local/bin/xray run -test -c "$D/xray.json" >/dev/null && echo "XRAY_CONFIG_OK"

cat > "$D/hy.yaml" <<EOF
listen: :443
tls:
  cert: $D/hy.crt
  key: $D/hy.key
auth:
  type: password
  password: $P
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
outbounds:
  - name: direct
    type: direct
EOF

cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray proxy (VLESS Reality)
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

systemctl daemon-reload
systemctl enable --now xray hysteria >/dev/null
echo "等待服务就绪..."
sleep 5
for s in xray hysteria; do
  echo "$s: $(systemctl is-active $s 2>/dev/null)"
done
ss -lnt 2>/dev/null | grep -E ':443 ' | awk '{print $1, $5}' || true
ss -lnu 2>/dev/null | grep -E ':443 ' | awk '{print $1, $5}' || true

echo "==> 本机自检"
cat > /tmp/hyc.yaml <<EOF
server: $IP4:443
auth: $P
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
VLESS_LINK="vless://$U@$IP4:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUB&sid=$SID&flow=xtls-rprx-vision#CDNShark-VLESS"
HY2_LINK="hysteria2://$P@$IP4:443?sni=www.bing.com&insecure=1#CDNShark-HY2"
{
  echo "$VLESS_LINK"
  echo "$HY2_LINK"
} > "$D/links.txt"
chmod 600 "$D/links.txt"
echo "VLESS_LINK=$VLESS_LINK"
echo "HY2_LINK=$HY2_LINK"
echo "节点已保存到 $D/links.txt"
echo DONE
