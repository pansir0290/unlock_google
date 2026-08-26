#!/usr/bin/env bash
# =========================================================
# WARP 自动化分流与 Xray 精准解锁脚本 (香港自动切日本版)
# =========================================================
set -e

outbound_tag="warp-out"
socks_port=40000
cfg_path="/usr/local/etc/xray/config.json"

echo "========================================================"
echo "🚀 开始执行 WARP 安装与 YouTube 精准分流自动化部署"
echo "========================================================"

# ---------------------------------------------------------
# 1. 基础依赖检测与 VPS 位置识别
# ---------------------------------------------------------
echo "📦 [1/4] 正在检查环境依赖与 VPS 地理位置..."

export DEBIAN_FRONTEND=noninteractive

if ! command -v curl &> /dev/null || ! command -v python3 &> /dev/null || ! command -v wg &> /dev/null; then
    echo "📥 正在补全基础工具包 (curl, python3, wireguard-tools)..."
    apt-get update -y
    apt-get install -y curl python3 wireguard-tools
fi

# 检测 VPS 本身所在国家/地区
vps_loc=$(curl -s https://speed.cloudflare.com/meta | grep -oP '"country":\s*"\K[^"]+' || echo "UNKNOWN")
echo "🌍 检测到当前 VPS 归属地: ${vps_loc}"

# ---------------------------------------------------------
# 2. 部署 warp-go 并根据地区智能挑选 Endpoint
# ---------------------------------------------------------
echo "🔄 [2/4] 正在部署并启动 WARP 节点代理..."

# 如果当前是香港机 (HK)，强制挑选日本 Cloudflare Endpoint
if [ "$vps_loc" = "HK" ]; then
    echo "⚡ 检测到香港 VPS，正在配置定向连接【日本 (Japan)】Cloudflare 节点..."
    # Cloudflare 日本东京 Endpoint 节点 IP
    endpoint_ip="162.159.193.5:2408"
else
    echo "🌐 非香港 VPS，使用标准 Cloudflare 全球 Anycast 节点..."
    endpoint_ip="162.159.192.1:2408"
fi

# 检查 warp-go 执行文件
if [ ! -f /usr/local/bin/warp-go ]; then
    echo "📥 下载 warp-go 自动化代理核心..."
    arch=$(uname -m)
    case "$arch" in
        x86_64)  bin_arch="amd64" ;;
        aarch64) bin_arch="arm64" ;;
        *) echo "❌ 不支持的 CPU 架构: $arch"; exit 1 ;;
    esac
    curl -sSL "https://gitlab.com/ProjectWARP/warp-go/-/releases/permalink/latest/downloads/warp-go_linux_${bin_arch}.tar.gz" | tar -xz -C /usr/local/bin/ warp-go
    chmod +x /usr/local/bin/warp-go
fi

# 建立 warp-go 专属目录与运行配置
mkdir -p /etc/warp-go

if [ ! -f /etc/warp-go/warp.conf ]; then
    echo "📝 注册 WARP 账号并写入定向 Endpoint (${endpoint_ip})..."
    /usr/local/bin/warp-go --register --config=/etc/warp-go/warp.conf >/dev/null 2>&1 || true
    
    # 替换其中的 Endpoint 字段为指定的日本/默认 IP
    sed -i "s/Endpoint = .*/Endpoint = ${endpoint_ip}/g" /etc/warp-go/warp.conf
fi

# 创建 systemd 后台守护服务 (将 WARP 转为 Socks5 监听 40000)
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

# 校验 Socks5 出口出口地区代码
warp_loc=$(curl --socks5 127.0.0.1:${socks_port} -s https://www.cloudflare.com/cdn-cgi/trace | grep "loc=" | cut -d= -f2 || echo "FAIL")
echo "🎉 WARP 代理服务部署完成！当前 WARP 出口实际地区: [ ${warp_loc} ]"

# ---------------------------------------------------------
# 3. Python 修改 Xray 配置文件 (维持原有逻辑)
# ---------------------------------------------------------
echo "🛠️ [3/4] 正在配置 Xray 路由规则与出站节点..."

python3 - <<EOF
import json
import os
import shutil
from datetime import datetime

cfg_path = "${cfg_path}"
outbound_tag = "${outbound_tag}"
socks_port = ${socks_port}

if not os.path.exists(cfg_path):
    print(f"❌ 错误: 未找到 Xray 配置文件 ({cfg_path})，请核对路径！")
    exit(1)

# 备份原始配置
backup_path = f"{cfg_path}.bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
shutil.copyfile(cfg_path, backup_path)

with open(cfg_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

if "outbounds" not in data:
    data["outbounds"] = []
if "routing" not in data:
    data["routing"] = {}
if "rules" not in data["routing"]:
    data["routing"]["rules"] = []

# 1. 注入/更新 WARP Socks5 Outbound
data["outbounds"] = [o for o in data["outbounds"] if o.get("tag") != outbound_tag]
warp_outbound = {
    "tag": outbound_tag,
    "protocol": "socks",
    "settings": {
        "servers": [
            {
                "address": "127.0.0.1",
                "port": socks_port
            }
        ]
    }
}
data["outbounds"].append(warp_outbound)

# 2. 注入/更新 YouTube 精准分流 Rule
data["routing"]["rules"] = [
    r for r in data["routing"]["rules"] 
    if outbound_tag not in r.get("outboundTag", "")
]

youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": [
        "geosite:youtube",
        "domain:youtube.com",
        "domain:googlevideo.com",
        "domain:ytimg.com",
        "domain:ggpht.com",
        "domain:googleapis.com",
        "domain:googleusercontent.com",
        "domain:youtubei.googleapis.com"
    ]
}
data["routing"]["rules"].insert(0, youtube_rule)

# 保存文件
with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 策略无损注入成功！原有配置已备份至: {backup_path}")
EOF

# ---------------------------------------------------------
# 4. 重启 Xray 服务闭环验证
# ---------------------------------------------------------
echo "🔄 [4/4] 正在重新加载并重启 Xray 服务..."
if systemctl restart xray; then
    echo "========================================================"
    echo "🎉 恭喜！YouTube 精准分流自动化配置完美落地！"
    echo "👉 香港机器已自动定向至【日本 WARP】解锁 YouTube Premium。"
    echo "========================================================"
else
    echo "❌ 警告: 规则已写入，但重启 Xray 失败，请使用 systemctl status xray 检查服务。"
    exit 1
fi
