#!/bin/bash

# =================================================================
# 脚本名称: unlock.sh (WARP + Xray 精准分流解锁 Google/YouTube)
# 修复内容: 
#   1. 采用 set +e 动态探测机制，彻底根治多轨兼容触发 set -e 导致脚本静默猝死 Bug
#   2. 失败时自动 fallback 打印官方 --help 帮助文档，拒绝任何调试盲区
# =================================================================

# 开启报错即退出机制（全局通用安全防线）
set -e

echo "========================================================"
echo "🚀 开始执行 终极全兼容 WARP + Xray 自动化分流解锁脚本"
echo "========================================================"

# 1. 环境检查与基础依赖安装
echo "🔄 [1/7] 检查并安装系统必要基础依赖..."
apt update -y
apt install curl lsb-release python3 gpg -y

# 2. 安装 Cloudflare WARP 客户端
if ! command -v warp-cli &> /dev/null; then
    echo "🔄 [2/7] 未检测到 WARP 客户端，开始配置官方源并安装..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt update -y
    apt install cloudflare-warp --no-install-recommends -y
    echo "✓ WARP 客户端轻量化内核安装成功！"
else
    echo "✓ [2/7] 检测到系统已存在 WARP 客户端，跳过安装步骤。"
fi

# 3. 强行激活并启动后台守护进程
echo "🔄 [3/7] 正在强制激活并启动 WARP 后台守护进程..."
systemctl daemon-reload
systemctl enable warp-svc --now
systemctl start warp-svc || true

echo "⏳ 正在等待 WARP 后台服务响应..."
for i in {1..10}; do
    if warp-cli status 2>&1 | grep -q -v "Unable to connect"; then
        echo "✓ WARP 后台守护进程对接成功！"
        break
    fi
    sleep 1
done

# 4. WARP 注册与服务条款接受
echo "🔄 [4/7] 正在初始化 WARP 账户注册..."
if ! warp-cli registration show &> /dev/null; then
    echo "👉 正在自动通过管道喂送 'y' 绕过交互，强制接受服务条款并完成注册..."
    yes | warp-cli registration new >/dev/null 2>&1 || warp-cli --accept-tos registration new >/dev/null 2>&1
    echo "✓ WARP 账户自动注册成功！"
else
    echo "✓ WARP 账户此前已注册，保持现状。"
fi

# 5. 配置 WARP 本地分流隧道模式 (🎯 核心安全探测闭环点)
echo "🔄 [5/7] 正在将 WARP 切换为本地 Socks5 代理分流模式..."

# 🔓 关键动作：暂时关闭报错即退出，允许安全的进行多版本语法探测
set +e

MODE_SUCCESS=0
if warp-cli mode set proxy >/dev/null 2>&1; then MODE_SUCCESS=1; echo "   ➔ [语法A] 成功切换为 Proxy 模式";
elif warp-cli mode proxy >/dev/null 2>&1; then MODE_SUCCESS=1; echo "   ➔ [语法B] 成功切换为 Proxy 模式";
elif warp-cli set-mode proxy >/dev/null 2>&1; then MODE_SUCCESS=1; echo "   ➔ [语法C] 成功切换为 Proxy 模式";
fi

PORT_SUCCESS=0
if warp-cli proxy set-port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1; echo "   ➔ [语法A] 成功锁定 40000 端口";
elif warp-cli proxy port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1; echo "   ➔ [语法B] 成功锁定 40000 端口";
elif warp-cli set-proxy-port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1; echo "   ➔ [语法C] 成功锁定 40000 端口";
fi

# 🔒 恢复报错即退出机制，保护后续流程
set -e

# 如果模式切换全部失败，打印调试信息并退出
if [ $MODE_SUCCESS -ne 1 ]; then
    echo "❌ 错误: 所有已知的 WARP 模式切换命令均失效！"
    echo "💡 自动化调试：以下是您当前系统安装的 WARP 允许的模式语法，请看提示："
    echo "--------------------------------------------------------"
    warp-cli mode --help || warp-cli --help || true
    echo "--------------------------------------------------------"
    exit 1
fi

# 如果端口配置全部失败，打印调试信息并退出
if [ $PORT_SUCCESS -ne 1 ]; then
    echo "❌ 错误: 所有已知的 WARP 端口监听命令均失效！"
    echo "💡 自动化调试：以下是您当前系统安装的 WARP 允许的代理端口语法："
    echo "--------------------------------------------------------"
    warp-cli proxy --help || true
    echo "--------------------------------------------------------"
    exit 1
fi

# 启动 WARP 连接
warp-cli connect

# 循环检查隧道是否真正握手成功
echo "⏳ 正在等待本地 40000 端口 WARP 隧道建立（最多等待 15 秒）..."
SUCCESS=0
for i in {1..15}; do
    if warp-cli status 2>&1 | grep -q "Connected"; then
        echo "🎉 WARP 隧道代理建立成功！本地 40000 端口已就绪。"
        SUCCESS=1
        break
    fi
    sleep 1
done

if [ $SUCCESS -ne 1 ]; then
    echo "❌ 错误: WARP 代理隧道未能按时建立成功，请检查节点连通性。"
    exit 1
fi

# 6. 补齐路由数据包与软链接，消灭路由黑洞
echo "🔄 [6/7] 正在自动下载最新的 geosite.dat 和 geoip.dat 路由数据包..."
mkdir -p /usr/local/share/xray/ /usr/local/bin/ /etc/xray/
curl -sSL -o /usr/local/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
curl -sSL -o /usr/local/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

ln -sf /usr/local/share/xray/geosite.dat /usr/local/bin/geosite.dat
ln -sf /usr/local/share/xray/geoip.dat /usr/local/bin/geoip.dat
ln -sf /usr/local/share/xray/geosite.dat /etc/xray/geosite.dat
ln -sf /usr/local/share/xray/geoip.dat /etc/xray/geoip.dat
echo "✓ 路由数据包多路径全局闭环完成！"

# 7. Xray 配置文件分流策略无损注入
echo "🔄 [7/7] 正在通过 Python3 智能解析并无损注入 Xray 分流规则..."

python3 - << 'EOF'
import json
import os
import sys

cfg_paths = ["/usr/local/etc/xray/config.json", "/etc/xray/config.json"]
cfg_path = None

for path in cfg_paths:
    if os.path.exists(path):
        cfg_path = path
        break

if not cfg_path:
    print("❌ 错误: 未找到 Xray 配置文件，请确认路径。")
    sys.exit(1)

with open(cfg_path, 'r', encoding='utf-8') as f:
    try:
        data = json.load(f)
    except Exception as e:
        print(f"❌ 错误: 读取 JSON 失败。详情: {e}")
        sys.exit(1)

backup_path = cfg_path + ".bak"
with open(backup_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

outbound_tag = "unlock-warp"
warp_outbound = {
    "tag": outbound_tag,
    "protocol": "socks",
    "settings": {
        "servers": [{"address": "127.0.0.1", "port": 40000}]
    },
    "streamSettings": {
        "sockopt": {
            "dialerProxy": "", 
            "domainStrategy": "UseIPv4"
        }
    }
}

if "outbounds" not in data: 
    data["outbounds"] = []

if not any(o.get("tag") == outbound_tag for o in data["outbounds"]):
    data["outbounds"].append(warp_outbound)

youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": ["geosite:youtube"]
}

if "routing" not in data: 
    data["routing"] = {"rules": []}
if "rules" not in data["routing"]: 
    data["routing"]["rules"] = []

rule_exists = any(
    outbound_tag in r.get("outboundTag", "") 
    for r in data["routing"]["rules"] 
    if "geosite:youtube" in str(r.get("domain", ""))
)

if not rule_exists:
    data["routing"]["rules"].insert(0, youtube_rule)

with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 策略无损注入成功！原有配置已备份至: {backup_path}")
EOF

# 重启服务验证闭环
echo "🔄 正在重新加载并重启 Xray 服务..."
if systemctl restart xray; then
    echo "========================================================"
    echo "🎉 恭喜！全套自动化配置成功！"
    echo "👉 后台已起、语法已避坑、体积已精简、YouTube 已强制分流！"
    echo "========================================================"
else
    echo "❌ 警告: 规则已写入，但重启 Xray 失败，请执行 'xray run -test -c /usr/local/etc/xray/config.json' 排查问题。"
fi
