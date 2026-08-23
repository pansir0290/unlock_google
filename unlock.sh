#!/usr/bin/env bash
# =========================================================
# WARP 自动化分流与 Xray 精准解锁脚本 (修复版)
# =========================================================
set -e

# 参数定义
outbound_tag="warp-out"
socks_port=40000
cfg_path="/usr/local/etc/xray/config.json"

echo "========================================================"
echo "🚀 开始执行 WARP 安装与 YouTube 精准分流自动化部署"
echo "========================================================"

# ---------------------------------------------------------
# 1. 系统环境与依赖库检测安装
# ---------------------------------------------------------
echo "📦 [1/4] 正在检查系统依赖与 Cloudflare WARP 客户端..."

export DEBIAN_FRONTEND=noninteractive

if ! command -v curl &> /dev/null || ! command -v gpg &> /dev/null || ! command -v python3 &> /dev/null; then
    echo "📥 正在补全基础工具包 (curl, gnupg, lsb-release, python3)..."
    apt-get update -y
    apt-get install -y curl gnupg lsb-release python3
fi

if ! command -v warp-cli &> /dev/null; then
    echo "📥 正在配置 Cloudflare 官方 APT 存储库..."
    mkdir -p /usr/share/keyrings
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

    echo "📥 正在安装 cloudflare-warp 二进制内核..."
    apt-get update -y
    apt-get install -y cloudflare-warp
    echo "✔ WARP 客户端内核安装成功！"
else
    echo "✔ 检测到 WARP 客户端已安装，跳过包下载阶段。"
fi

# ---------------------------------------------------------
# 2. 守护进程启动与 WARP 交互注册 (已修复 Expect 卡死)
# ---------------------------------------------------------
echo "🔄 [2/4] 正在启动 WARP 后台守护进程并执行账户注册..."

systemctl enable --now warp-svc >/dev/null 2>&1 || true
sleep 1

# 状态校验与自动化注册
if warp-cli status 2>&1 | grep -q "Connected"; then
    echo "✔ WARP 客户端已处于连接状态，无需重复注册。"
else
    # 尝试清除残余旧注册，防止弹出 Old registration is still around 阻止后续操作
    warp-cli registration delete >/dev/null 2>&1 || true

    echo "📝 正在自动接受 Cloudflare 服务条款并注册设备..."
    # 彻底摒弃易卡死退出的 expect 脚本，使用管道回车强制送入 'y'
    echo "y" | warp-cli registration new >/dev/null 2>&1 || {
        yes | warp-cli registration new >/dev/null 2>&1 || true
    }

    echo "⚙️ 正在切换 WARP 至 Socks5 代理模式..."
    warp-cli mode proxy
    warp-cli proxy port ${socks_port} >/dev/null 2>&1 || true

    echo "🔌 正在建立 WARP 边缘网络连接..."
    warp-cli connect
    sleep 3
fi

# 确认 WARP 状态
if warp-cli status 2>&1 | grep -E -q "Connected|Success"; then
    echo "✔ WARP 后台守护进程对接成功！Socks5 监听端口: ${socks_port}"
else
    echo "⚠️ 警告: WARP 状态未显式返回 Connected，继续执行 Xray 规则注入..."
fi

# ---------------------------------------------------------
# 3. Python 精准修改 Xray 配置文件 (出站 + 路由)
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

# 确保必要的结构层级存在
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
        "geosite:youtube"
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
    echo "👉 YouTube 流量已成功引导至 WARP 解锁节点。"
    echo "========================================================"
else
    echo "❌ 警告: 规则已写入，但重启 Xray 失败，请使用 systemctl status xray 检查服务。"
    exit 1
fi
