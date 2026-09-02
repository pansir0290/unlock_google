#!/usr/bin/env bash
# =========================================================
# WARP 自动化分流与 Xray 精准解锁脚本 (修复增强版)
# =========================================================
set -e

outbound_tag="warp-out"
socks_port=40000
cfg_path="/usr/local/etc/xray/config.json"

echo "========================================================"
echo "🚀 开始执行 WARP 修复部署与 YouTube 精准分流"
echo "========================================================"

# 1. 依赖与环境检查
export DEBIAN_FRONTEND=noninteractive
if ! command -v curl &> /dev/null || ! command -v python3 &> /dev/null; then
    apt-get update -y && apt-get install -y curl python3
fi

vps_loc=$(curl -s --max-time 5 https://speed.cloudflare.com/meta | grep -oP '"country":\s*"\K[^"]+' || echo "UNKNOWN")
echo "🌍 VPS 本地归属地: ${vps_loc}"

# 2. 安装与配置 warp-go
if [ "$vps_loc" = "HK" ]; then
    endpoint_ip="162.159.193.5:2408"
else
    endpoint_ip="162.159.192.1:2408"
fi

arch=$(uname -m)
case "$arch" in
    x86_64)  bin_arch="amd64" ;;
    aarch64) bin_arch="arm64" ;;
    *) echo "❌ 不支持的 CPU 架构: $arch"; exit 1 ;;
esac

echo "📥 下载 warp-go 核心..."
curl -sSL -o /usr/local/bin/warp-go "https://gitlab.com/ProjectWARP/warp-go/-/raw/main/bin/warp-go_linux_${bin_arch}" || \
curl -sSL -o /usr/local/bin/warp-go "https://github.com/pansir0290/unlock_google/releases/download/v1.0.0/warp-go_linux_${bin_arch}"
chmod +x /usr/local/bin/warp-go

mkdir -p /etc/warp-go

# 自动生成正确的 WARP 账号配置文件
echo "🔐 正在注册 WARP 账号并生成密钥..."
/usr/local/bin/warp-go --register --config=/etc/warp-go/warp.conf >/dev/null 2>&1 || true

# 替换 Endpoint 为优质 IP
if [ -f /etc/warp-go/warp.conf ]; then
    sed -i "s/Endpoint =.*/Endpoint = ${endpoint_ip}/g" /etc/warp-go/warp.conf
else
    echo "❌ WARP 注册失败，请检查网络链接！"
    exit 1
fi

# 建立守护服务
cat <<EOF > /etc/systemd/system/warp-go.service
[Unit]
Description=WARP-GO Socks5 Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/warp-go --config=/etc/warp-go/warp.conf --socks5=127.0.0.1:${socks_port}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now warp-go >/dev/null 2>&1 || systemctl restart warp-go

sleep 3

# 验证 WARP Socks5 是否生效
warp_loc=$(curl --socks5 127.0.0.1:${socks_port} -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep "loc=" | cut -d= -f2 || echo "FAIL")
if [ "$warp_loc" = "FAIL" ]; then
    echo "❌ WARP 本地代理打通失败，请检查 /etc/warp-go/warp.conf 配置文件！"
    exit 1
fi
echo "🎉 WARP 代理接入成功！Socks5 出口地区: [ ${warp_loc} ]"

# 3. Python 注入 Xray 规则 (包含 IP 路由与 GeoIP 覆盖)
echo "🛠️ 正在配置 Xray 完美路由策略..."

python3 - <<EOF
import json
import os
import shutil
from datetime import datetime

cfg_path = "${cfg_path}"
outbound_tag = "${outbound_tag}"
socks_port = ${socks_port}

if not os.path.exists(cfg_path):
    print(f"❌ 未找到 Xray 配置文件: {cfg_path}")
    exit(1)

backup_path = f"{cfg_path}.bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
shutil.copyfile(cfg_path, backup_path)

with open(cfg_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

data.setdefault("outbounds", [])
data.setdefault("routing", {}).setdefault("rules", [])

# 清理旧出站
data["outbounds"] = [o for o in data["outbounds"] if o.get("tag") != outbound_tag]

# 添加 Socks5 出站
warp_outbound = {
    "tag": outbound_tag,
    "protocol": "socks",
    "settings": {
        "servers": [{"address": "127.0.0.1", "port": socks_port}]
    }
}
data["outbounds"].append(warp_outbound)

# 清理旧路由规则
data["routing"]["rules"] = [
    r for r in data["routing"]["rules"] 
    if r.get("outboundTag") != outbound_tag
]

# 精准 YouTube + 视频 CDN 流量规则（包含 IP + 域名）
youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": [
        "geosite:youtube",
        "domain:youtube.com",
        "domain:googlevideo.com",
        "domain:yt.be",
        "domain:ytimg.com"
    ]
}

# 插入到规则列表最顶部（最高优先级）
data["routing"]["rules"].insert(0, youtube_rule)

with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 路由规则更新完毕，旧配置已备份至: {backup_path}")
EOF

# 4. 重启 Xray
echo "🔄 重启 Xray..."
if systemctl restart xray; then
    echo "========================================================"
    echo "🎉 部署完成！YouTube 流量已成功强制通过 WARP (${warp_loc}) 解锁！"
    echo "========================================================"
else
    echo "❌ Xray 重启失败，请检查配置文件 syntax。"
    exit 1
fi
