#!/bin/bash

# ==========================================================
# 脚本名称: CF WARP + Xray (YouTube & Gemini) 双重分流一键脚本
# 适用系统: Ubuntu / Debian (Root 用户)
# 修复特性: 自动解锁DNS、静默接受条款、自动补全缺失的路由数据包
# ==========================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}====================================================${NC}"
echo -e "${GREEN}    开始执行 CF WARP + Xray (YT+Gemini) 自动化配置     ${NC}"
echo -e "${YELLOW}====================================================${NC}"

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 错误: 请使用 root 用户或 sudo 运行此脚本！${NC}"
    exit 1
fi

CONFIG_PATH="/usr/local/etc/xray/config.json"
PROXY_PORT=40000

# 2. 检查 Xray 配置文件路径
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${RED}❌ 错误: 未能在路径 $CONFIG_PATH 找到 Xray 配置文件！${NC}"
    exit 1
fi

# [1/6] 修复 DNS 锁死问题
echo -e "${YELLOW}[1/6] 正在优化系统 DNS 解析，规避商家解锁污染...${NC}"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo -e "${GREEN}✓ 系统 DNS 已成功修改为 8.8.8.8 和 1.1.1.1${NC}"

# [2/6] 安装组件 & 修复 geosite 缺失导致的节点不通问题
echo -e "${YELLOW}[2/6] 正在安装基础组件、下载路由数据库及 WARP 官方客户端...${NC}"
apt update && apt install curl gpg lsb-release python3 -y

echo -e "${YELLOW}🔄 正在自动下载最新的 geosite.dat 和 geoip.dat 路由数据包...${NC}"
curl -sSL -o /usr/local/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
curl -sSL -o /usr/local/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
echo -e "${GREEN}✓ 路由数据包已成功补齐到 /usr/local/bin/ 目录${NC}"

# 配置 WARP 官方源
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

apt update && apt install cloudflare-warp -y
echo -e "${GREEN}✓ WARP 官方客户端安装成功！${NC}"

# [3/6] 修复非交互环境下 WARP 条款卡死退出问题
echo -e "${YELLOW}[3/6] 正在初始化并配置 WARP 代理模式...${NC}"
sleep 2
echo "y" | warp-cli registration new 2>/dev/null || true
warp-cli mode proxy
warp-cli proxy port $PROXY_PORT
warp-cli connect
systemctl enable warp-svc --now

echo -e "${YELLOW}正在等待 WARP 建立隧道（大约需要 5 秒）...${NC}"
sleep 5

# [4/6] 代理可用性检测
echo -e "${YELLOW}[4/6] 正在对本地 40000 端口进行 Google 回归测试...${NC}"
HTTP_STATUS=$(curl -x socks5h://127.0.0.1:$PROXY_PORT -sI https://www.google.com | grep -iE "HTTP/" | awk '{print $2}')

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}✓ 完美！WARP 本地代理网络测试成功，响应状态: 200${NC}"
else
    echo -e "${RED}❌ 警告: WARP 本地通道测试返回异常状态 [${HTTP_STATUS}]。${NC}"
fi

# [5/6] 自动备份防炸
echo -e "${YELLOW}[5/6] 正在备份原 Xray 配置文件...${NC}"
cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"
echo -e "${GREEN}✓ 备份完成。备份文件保存在: ${CONFIG_PATH}.bak${NC}"

# [6/6] 使用 Python 精准无损注入 JSON
echo -e "${YELLOW}[6/6] 正在使用 Python 精准注入出站与双重分流规则...${NC}"
python3 << 'EOF'
import json
import sys

path = "/usr/local/etc/xray/config.json"
port = 40000

try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"❌ 错误: 解析 Xray 原 JSON 文件失败: {e}")
    sys.exit(1)

warp_outbound = {
    "tag": "warp-out",
    "protocol": "socks",
    "settings": {
        "servers": [
            {
                "address": "127.0.0.1",
                "port": port
            }
        ]
    }
}

combined_domains = [
    "geosite:youtube",
    "domain:googlevideo.com",
    "domain:youtubei.googleapis.com",
    "domain:ytimg.com",
    "domain:gemini.google.com",
    "domain:aistudio.google.com",
    "domain:generativelanguage.googleapis.com",
    "domain:proactivebackend-pa.googleapis.com",
    "domain:alkalimaven-pa.googleapis.com"
]

split_rule = {
    "type": "field",
    "outboundTag": "warp-out",
    "domain": combined_domains
}

if 'outbounds' in data:
    if not any(o.get('tag') == 'warp-out' for o in data['outbounds']):
        data['outbounds'].append(warp_outbound)
else:
    data['outbounds'] = [warp_outbound]

if 'routing' in data and 'rules' in data['routing']:
    data['routing']['rules'] = [r for r in data['routing']['rules'] if r.get('outboundTag') != 'warp-out']
    data['routing']['rules'].insert(0, split_rule)
else:
    if 'routing' not in data: data['routing'] = {'rules': []}
    if 'rules' not in data['routing']: data['routing']['rules'] = []
    data['routing']['rules'].insert(0, split_rule)

with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print("✓ Python (YouTube + Gemini) 规则动态注入成功！")
EOF

# 启动与最终安全测试
echo -e "${YELLOW}正在全力重启 Xray 服务...${NC}"
systemctl restart xray

# 自动调用测试命令进行验证，防止语法意外损坏导致断流
if xray run -test -c "$CONFIG_PATH" >/dev/null 2>&1; then
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}====================================================${NC}"
        echo -e "${GREEN}🎉 恭喜！全套自动化配置成功！YouTube & Gemini 分流全生效。${NC}"
        echo -e "${GREEN}====================================================${NC}"
    else
        echo -e "${RED}❌ 错误: Xray 配置校验通过但服务未能成功运行，请检查 443 端口是否被抢占。${NC}"
    fi
else
    echo -e "${RED}❌ 错误: 发现最终配置文件语法校验未通过！正在为您自动回滚备份...${NC}"
    cp "${CONFIG_PATH}.bak" "$CONFIG_PATH"
    systemctl restart xray
    echo -e "${YELLOW}↩️ 已成功回滚至最初的备份状态，节点已恢复原样。${NC}"
fi
