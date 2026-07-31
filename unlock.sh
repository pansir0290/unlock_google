#!/bin/bash

# =================================================================
# 脚本名称: unlock.sh (WARP + Xray 精准分流 YouTube 解锁)
# 说明: 自动安装配置 WARP 客户端，并在 Xray 配置中精准注入 YouTube 分流
# =================================================================

# 开启报错即退出机制
set -e

echo "========================================================"
echo "🚀 开始执行 WARP + Xray 自动化分流解锁脚本"
echo "========================================================"

# 1. 环境检查与基础依赖安装
echo "🔄 [1/7] 检查并安装系统必要基础依赖..."
if command -v apt &> /dev/null; then
    apt update -y && apt install curl lsb-release python3 gpg expect -y
elif command -v yum &> /dev/null; then
    yum install epel-release -y && yum install curl python3 expect gpg -y
fi

# 2. 安装 Cloudflare WARP 客户端
if ! command -v warp-cli &> /dev/null; then
    echo "🔄 [2/7] 未检测到 WARP 客户端，开始配置官方源并安装..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt update -y && apt install cloudflare-warp --no-install-recommends -y
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

# 4. WARP 注册与服务条款接受 (通过 expect 仿真键盘输入)
echo "🔄 [4/7] 正在初始化 WARP 账户注册..."

set +e
REG_SUCCESS=0

if warp-cli registration show >/dev/null 2>&1 || warp-cli account >/dev/null 2>&1; then
    REG_SUCCESS=1
    echo "   ➔ 检测到账户先前已存在，自动跳过注册雷区。"
fi

if [ $REG_SUCCESS -ne 1 ]; then
    echo "   👉 检测到未注册设备。正在通过 expect 引擎全面托管 PTY 键盘流..."
    
    expect << 'EOF'
    set timeout 15
    spawn warp-cli registration new
    expect {
        "Accept Terms of Service" { send "y\r"; exp_continue }
        "y/N"                     { send "y\r"; exp_continue }
        "already exists"          { exit 0 }
        eof
    }
EOF
    
    sleep 1.5

    if warp-cli registration show >/dev/null 2>&1 || warp-cli account >/dev/null 2>&1; then
        REG_SUCCESS=1
        echo "   ➔ [expect 强配成功] 已强制通过服务条款，WARP 账户注册成功！"
    fi
fi

set -e

if [ $REG_SUCCESS -ne 1 ]; then
    echo "❌ 错误: expect 自动化引擎未能击穿条款拦截。"
    echo "💡 请手动运行: warp-cli registration new，输入 y 同意后重新运行此脚本！"
    exit 1
fi

# 5. 配置 WARP 本地分流隧道模式 
echo "🔄 [5/7] 正在将 WARP 切换为本地 Socks5 代理分流模式..."

set +e
MODE_SUCCESS=0
if warp-cli mode set proxy >/dev/null 2>&1; then MODE_SUCCESS=1;
elif warp-cli mode proxy >/dev/null 2>&1; then MODE_SUCCESS=1;
elif warp-cli set-mode proxy >/dev/null 2>&1; then MODE_SUCCESS=1;
fi

PORT_SUCCESS=0
if warp-cli proxy set-port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1;
elif warp-cli proxy port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1;
elif warp-cli set-proxy-port 40000 >/dev/null 2>&1; then PORT_SUCCESS=1;
fi
set -e

if [ $MODE_SUCCESS -ne 1 ] || [ $PORT_SUCCESS -ne 1 ]; then
    echo "❌ 错误: WARP 模式或端口切换失败！"
    exit 1
fi

warp-cli connect

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

# 6. 补齐路由数据包与软链接
echo "🔄 [6/7] 正在自动下载最新的 geosite.dat 和 geoip.dat 路由数据包..."
mkdir -p /usr/local/share/xray/ /usr/local/bin/ /etc/xray/
curl -sSL -o /usr/local/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
curl -sSL -o /usr/local/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

ln -sf /usr/local/share/xray/geosite.dat /usr/local/bin/geosite.dat
ln -sf /usr/local/share/xray/geoip.dat /usr/local/bin/geoip.dat
ln -sf /usr/local/share/xray/geosite.dat /etc/xray/geosite.dat
ln -sf /usr/local/share/xray/geoip.dat /etc/xray/geoip.dat
echo "✓ 路由数据包多路径全局闭环完成！"

# 7. Xray 配置文件分流策略智能无损注入（精准锁定 YouTube 避免污染其他谷歌服务）
echo "🔄 [7/7] 正在通过 Python3 智能解析并无损注入 YouTube 分流规则..."

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

# 幂等更新 Outbound
data["outbounds"] = [o for o in data["outbounds"] if o.get("tag") != outbound_tag]
data["outbounds"].append(warp_outbound)

# 确保 routing 存在并优化 domainStrategy 为 IPOnDemand
if "routing" not in data: 
    data["routing"] = {}
data["routing"]["domainStrategy"] = "IPOnDemand"

if "rules" not in data["routing"]: 
    data["routing"]["rules"] = []

# 清理旧的规则防止重复累加
data["routing"]["rules"] = [
    r for r in data["routing"]["rules"] 
    if outbound_tag not in r.get("outboundTag", "")
]

# 插入精准的 YouTube 专享分流规则（不污染全局 Google）
youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": [
        "geosite:youtube"
    ]
}

data["routing"]["rules"].insert(0, youtube_rule)

with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 策略无损注入成功！原有配置已备份至: {backup_path}")
EOF

# 重启服务验证闭环
echo "🔄 正在重新加载并重启 Xray 服务..."
if systemctl restart xray; then
    echo "========================================================"
    echo "🎉 恭喜！YouTube 精准分流自动化配置完美落地！"
    echo "👉 YouTube 流量已成功引导至 WARP 解锁节点。"
    echo "========================================================"
else
    echo "❌ 警告: 规则已写入，但重启 Xray 失败，请检查服务状态。"
    exit 1
fi
