# Mihomo 一键安装

Debian/Ubuntu + systemd 的 amd64/arm64 LXC。默认开启 TUN、双栈 Fake-IP、服务开机自启和异常重启。只接管 Fake-IP 网段，适合爱快 + 独立 OxiDNS。

容器里以 root 执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-install/main/install.sh -o /tmp/install-mihomo.sh && bash /tmp/install-mihomo.sh
```

安装到 `/opt/mihomo`。重复运行升级官方稳定内核，校验 SHA256，并保留原配置。旧文件存入 `backups/`，升级失败不会自动恢复，可从备份恢复。

## 修改配置

编辑 `/opt/mihomo/config.yaml`，在 `proxies` 添加自己的节点，或取消 `proxy-providers` 和代理组 `use` 的注释并填写订阅。未配节点时默认 REJECT，不会提供有效代理。配置注释已说明如何修改。

```bash
/opt/mihomo/mihomo -t -d /opt/mihomo -f /opt/mihomo/config.yaml
systemctl restart mihomo
systemctl status mihomo --no-pager
journalctl -u mihomo -f
```

管理 API 仅监听 `127.0.0.1:9090`，HTTP/SOCKS 混合端口仅本机 `7890`，未附带 Web 面板；DNS 在 IPv4 `7874`，可查询 A/AAAA，防火墙仅允许可信 LAN 使用。需要远程管理时自行绑定 LAN IP 并配置 secret。

## LXC / 爱快 / OxiDNS

- 容器须能创建 `/dev/net/tun`，拥有网络管理权限。脚本会实测 TUN，并配置双栈转发。
- 宿主机也须设置 LXC 开机自启动。脚本不修改宿主机，也不清空防火墙。
- OxiDNS 国外上游：`udp://Mihomo容器IPv4:7874`。
- 爱快路由 `198.18.0.0/16` 到容器 LAN IPv4，`fdfe:dcba:9876::/64` 到容器真实、稳定的 LAN IPv6。不要把 TUN 地址作为爱快下一跳。
- 国内真实 IP 保持直连；Fake-IP 网段与配置需一致且无冲突。已有 TProxy 接管规则需先停用，避免与 TUN 重叠。
- 多网卡环境需检查出口识别与 IPv6 RA 接口；脚本按默认 IPv4 出口接口设置 RA。容器防火墙还需允许必要流量和 ICMPv6。

脚本和模板不含订阅、账号或节点凭证。需要能访问 GitHub API/Release；不使用第三方下载镜像。

参考：[Mihomo](https://github.com/MetaCubeX/mihomo)、[DNS](https://wiki.metacubex.one/config/dns/)、[TUN](https://wiki.metacubex.one/config/inbound/tun/)。
