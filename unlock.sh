#!/usr/bin/env bash
# =========================================================
# WARP 自动化分流与 Xray 精准解锁脚本 (完整完美修正版)
# =========================================================
set -e

outbound_tag="warp-out"
socks_port=40000
cfg_path="/usr/local/etc/xray/config.json"

echo "========================================================"
echo "🚀 开始执行 WARP 安装与 YouTube 精准分流自动化部署"
echo "========================================================"

# 1. 基础依赖与 Cloudflare WARP 安装
export DEBIAN_FRONTEND=noninteractive
if ! command -v curl &> /dev/null || ! command -v gpg &> /dev/null || ! command -v python3 &> /dev/null || ! command -v script &> /dev/null; then
    apt-get update -y && apt-get install -y curl gnupg lsb-release python3 bsdutils
fi

if ! command -v warp-cli &> /dev/null; then
    mkdir -p /usr/share/keyrings
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -y && apt-get install -y cloudflare-warp
fi

# 2. WARP 后台服务注册与代理模式设置
systemctl enable --now warp-svc >/dev/null 2>&1 || true
sleep 1

if ! warp-cli status 2>&1 | grep -q "Connected"; then
    warp-cli registration delete >/dev/null 2>&1 || true
    script -q -c "warp-cli registration new" /dev/null <<EOF
y
EOF
    script -q -c "warp-cli mode proxy" /dev/null <<EOF
y
EOF
    warp-cli proxy port ${socks_port} >/dev/null 2>&1 || true
    warp-cli connect
    sleep 3
fi

# 3. 补全 GeoIP 和 Geosite 规则文件 (关键步骤)
echo "📦 正在补全 Xray 路由规则数据库 (geosite/geoip)..."
mkdir -p /usr/local/share/xray/
curl -L -o /usr/local/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/geosite.dat
curl -L -o /usr/local/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

# 4. 修改 Xray 配置文件
echo "🛠️ 正在配置 Xray 路由规则与 WARP 出站..."
python3 - <<EOF
import json
import os
import shutil
from datetime import datetime

cfg_path = "${cfg_path}"
outbound_tag = "${outbound_tag}"
socks_port = ${socks_port}

if not os.path.exists(cfg_path):
    print(f"❌ 错误: 未找到 Xray 配置文件 ({cfg_path})")
    exit(1)

# 备份
backup_path = f"{cfg_path}.bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
shutil.copyfile(cfg_path, backup_path)

with open(cfg_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

# 补全基础结构
if "outbounds" not in data: data["outbounds"] = []
if "routing" not in data: data["routing"] = {}
if "rules" not in data["routing"]: data["routing"]["rules"] = []

# 开启 DNS 内置解析
data["dns"] = {"servers": ["1.1.1.1", "8.8.8.8", "localhost"]}
data["routing"]["domainStrategy"] = "IPIfNonMatch"

# 1. 注入 WARP Outbound (开启 UDP 支持)
data["outbounds"] = [o for o in data["outbounds"] if o.get("tag") != outbound_tag]
warp_outbound = {
    "tag": outbound_tag,
    "protocol": "socks",
    "settings": {
        "servers": [{"address": "127.0.0.1", "port": socks_port, "users": []}],
        "udp": True
    }
}
data["outbounds"].append(warp_outbound)

# 2. 注入 YouTube 安全分流规则
data["routing"]["rules"] = [r for r in data["routing"]["rules"] if r.get("outboundTag") != outbound_tag]
youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": [
        "geosite:youtube",
        "domain:youtube.com",
        "domain:googlevideo.com",
        "domain:ytimg.com",
        "domain:ggpht.com",
        "domain:youtu.be"
    ]
}
data["routing"]["rules"].insert(0, youtube_rule)

with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 配置注入成功！备份文件: {backup_path}")
EOF

# 5. 重启 Xray 服务
echo "🔄 正在重启 Xray 服务..."
systemctl restart xray
if systemctl is-active --quiet xray; then
    echo "🎉 部署完成！YouTube 流量已成功走 WARP 解锁。"
else
    echo "❌ 重启失败，请运行 systemctl status xray 查看详细日志。"
fi
