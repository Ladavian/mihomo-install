#!/usr/bin/env bash
# Debian/Ubuntu systemd LXC，amd64/arm64；重复运行保留原配置。
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]] || { echo '请使用 root 运行。'; exit 1; }
[[ -d /run/systemd/system ]] && command -v apt-get >/dev/null || { echo '需要 Debian/Ubuntu + systemd。'; exit 1; }
[[ -c /dev/net/tun ]] || { echo '缺少 /dev/net/tun，请先在 LXC 宿主机开放 TUN。'; exit 1; }
case $(uname -m) in
  x86_64) arch=amd64-compatible ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo '仅支持 amd64/arm64。'; exit 1 ;;
esac
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates python3 gzip iproute2 procps
python3 - <<'PY'
import os, fcntl, struct
fd = os.open('/dev/net/tun', os.O_RDWR)
fcntl.ioctl(fd, 0x400454ca, struct.pack('16sH', b'mh-test%d', 0x1001))
os.close(fd)
PY

mkdir -p /opt/mihomo
tmp=$(mktemp -d /opt/mihomo/.install.XXXXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
  https://api.github.com/repos/MetaCubeX/mihomo/releases/latest -o "$tmp/release.json"
python3 - "$tmp/release.json" "$arch" > "$tmp/asset" <<'PY'
import json, re, sys
r = json.load(open(sys.argv[1]))
name = f"mihomo-linux-{sys.argv[2]}-{r['tag_name']}.gz"
a = next((a for a in r['assets'] if a['name'] == name), None)
if not a or not re.fullmatch(r'sha256:[0-9a-fA-F]{64}', a.get('digest') or ''):
    raise SystemExit('找不到官方资产或 SHA256 校验值。')
if not a['browser_download_url'].startswith('https://github.com/MetaCubeX/mihomo/releases/download/'):
    raise SystemExit('官方资产下载地址异常。')
print(a['browser_download_url'])
print(a['digest'].split(':')[1])
PY
curl -fSL --retry 3 --connect-timeout 15 --max-time 600 \
  "$(sed -n '1p' "$tmp/asset")" -o "$tmp/mihomo.gz"
printf '%s  %s\n' "$(sed -n '2p' "$tmp/asset")" "$tmp/mihomo.gz" | sha256sum -c -
gzip -dc "$tmp/mihomo.gz" > "$tmp/mihomo"
chmod 755 "$tmp/mihomo"
if [[ ! -f /opt/mihomo/config.yaml ]]; then
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
    https://raw.githubusercontent.com/Ladavian/mihomo-install/main/config.yaml -o "$tmp/config.yaml"
else
  cp /opt/mihomo/config.yaml "$tmp/config.yaml"
fi
"$tmp/mihomo" -t -d /opt/mihomo -f "$tmp/config.yaml"

# 持久化双栈转发；保留出口接口 RA，避免 IPv6 forwarding 后丢失默认路由。
iface=$(ip -4 route get 223.5.5.5 | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n1)
[[ "$iface" =~ ^[a-zA-Z0-9_.:-]+$ ]] || { echo '无法识别出口网卡。'; exit 1; }
cat > "$tmp/sysctl.conf" <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.${iface}.accept_ra = 2
EOF
v4=$(sysctl -n net.ipv4.ip_forward)
v6=$(sysctl -n net.ipv6.conf.all.forwarding)
ra=$(sysctl -n "net.ipv6.conf.${iface}.accept_ra")
if ! sysctl -q -p "$tmp/sysctl.conf"; then
  sysctl -q -w "net.ipv4.ip_forward=$v4" "net.ipv6.conf.all.forwarding=$v6" "net.ipv6.conf.${iface}.accept_ra=$ra" || true
  echo 'LXC 无法开启网络转发，请检查宿主机权限。'; exit 1
fi
backup="/opt/mihomo/backups/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
for f in /opt/mihomo/mihomo /opt/mihomo/config.yaml /etc/systemd/system/mihomo.service /etc/sysctl.d/90-mihomo.conf; do
  [[ ! -f "$f" ]] || cp -p "$f" "$backup/$(basename "$f")"
done
install -m 755 "$tmp/mihomo" /opt/mihomo/mihomo.new
mv -f /opt/mihomo/mihomo.new /opt/mihomo/mihomo
[[ -f /opt/mihomo/config.yaml ]] || install -m 600 "$tmp/config.yaml" /opt/mihomo/config.yaml
install -m 644 "$tmp/sysctl.conf" /etc/sysctl.d/90-mihomo.conf
cat > /etc/systemd/system/mihomo.service <<'EOF'
[Unit]
Description=Mihomo
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0
[Service]
WorkingDirectory=/opt/mihomo
ExecStartPre=/usr/sbin/sysctl -q -p /etc/sysctl.d/90-mihomo.conf
ExecStart=/opt/mihomo/mihomo -d /opt/mihomo -f /opt/mihomo/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=1048576
UMask=0077
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo
sleep 3
systemctl is-active --quiet mihomo || { echo '启动失败：journalctl -u mihomo -n 60'; exit 1; }
echo "安装完成，已开启 TUN 和服务自启。备份：$backup"
echo '配置：/opt/mihomo/config.yaml（首次需要自行添加节点/订阅）'
echo '修改后：systemctl restart mihomo；日志：journalctl -u mihomo -f'
echo '宿主机上还需开启 LXC 容器的开机自启动，并配置爱快双栈 Fake-IP 路由。'
