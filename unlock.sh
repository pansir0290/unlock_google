#!/bin/bash

# =================================================================
# 脚本名称: unlock.sh (WARP + Xray 精准分流解锁 Google/YouTube)
# 修复内容: 
#   1. 解决新版 warp-cli 强制弹窗接受服务条款(TOS)导致的死锁
#   2. 解决 --no-install-recommends 导致 daemon 守护进程未启动报错
#   3. 全面兼容新/老/过渡版 warp-cli 变态的模式与端口配置语法
# =================================================================

# 开启报错即退出机制
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
    
    # 导入官方 GPG 密钥
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    
    # 写入官方 APT 源
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    # 更新源并安装（使用 --no-install-recommends 极致瘦身，拒绝桌面图形垃圾包）
    apt update -y
    apt install cloudflare-warp --no-install-recommends -y
    echo "✓ WARP 客户端轻量化内核安装成功！"
else
    echo "✓ [2/7] 检测到系统已存在 WARP 客户端，跳过安装步骤。"
fi

# 3. 强行激活并启动后台守护进程 (🎯 根治 Unable to connect to daemon 报错)
echo "🔄 [3/7] 正在强制激活并启动 WARP 后台守护进程..."
systemctl daemon-reload
systemctl enable warp-svc --now
systemctl start warp-svc || true

# 循环检查，确保 daemon 彻底就绪再往下跑，防止 cli 找不到家
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

# 5. 配置 WARP 本地分流隧道模式 (🎯 针对新老版本语法多轨轰炸兼容)
echo "🔄 [5/7] 正在将 WARP 切换为本地 Socks5 代理分流模式..."

# 模式切换兼容：尝试新版语法、标准语法、历史语法
warp-cli mode set proxy >/dev/null 2>&1 || warp-cli mode proxy >/dev/null 2>&1 || warp-cli set-mode proxy >/dev/null 2>&1

# 端口锁定兼容：尝试锁定 40000 端口
warp-cli proxy set-port 40000 >/dev/null 2>&1 || warp-cli proxy port 40000 >/dev/null 2>&1 || warp-cli set-proxy-port 40000 >/dev/null 2>&1

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

# 兼容常见的主流 Xray 路径
cfg_paths = ["/usr/local/etc/xray/config.json", "/etc/xray/config.json"]
cfg_path = None

for path in cfg_paths:
    if os.path.exists(path):
        cfg_path = path
        break

if not cfg_path:
    print("❌ 错误: 未找到 Xray 配置文件，请确认你的 Xray 配置文件路径是否为标准路径。")
    sys.exit(1)

# 读取现有的配置文件
with open(cfg_path, 'r', encoding='utf-8') as f:
    try:
        data = json.load(f)
    except Exception as e:
        print(f"❌ 错误: 读取 JSON 失败，可能存在配置语法错误。详情: {e}")
        sys.exit(1)

# 创建备份文件
backup_path = cfg_path + ".bak"
with open(backup_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

# 1. 构造 WARP 出站结构 (强制走 IPv4 握手绕过限制)
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

# 2. 构造 YouTube 强路由分流规则
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
    # 插入到路由规则的最顶部 (索引0)，确保最高优先级拦截
    data["routing"]["rules"].insert(0, youtube_rule)

# 重新回写配置文件
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
