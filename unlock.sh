#!/bin/bash

# ==========================================================
# 脚本名称: CF WARP + Xray (YouTube + Gemini) 双重分流一键脚本
# 适用系统: Ubuntu / Debian (Root 用户)
# ==========================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}====================================================${NC}"
echo -e "${GREEN}    开始执行 CF WARP + Xray (YT+Gemini) 自动化配置     ${NC}"
echo -e "${YELLOW}====================================================${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 错误: 请使用 root 用户或 sudo 运行此脚本！${NC}"
    exit 1
fi

CONFIG_PATH="/usr/local/etc/xray/config.json"
PROXY_PORT=40000

if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${RED}❌ 错误: 未能在路径 $CONFIG_PATH 找到 Xray 配置文件！${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/6] 正在优化系统 DNS 解析，规避商家解锁污染...${NC}"
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo -e "${GREEN}✓ 系统 DNS 已成功修改为 8.8.8.8 和 1.1.1.1${NC}"

echo -e "${YELLOW}[2/6] 正在安装基础组件及 Cloudflare WARP 官方客户端...${NC}"
apt update && apt install curl gpg lsb-release python3 -y

curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list

apt update && apt install cloudflare-warp -y
echo -e "${GREEN}✓ WARP 客户端安装成功！${NC}"

echo -e "${YELLOW}[3/6] 正在初始化并配置 WARP 代理模式...${NC}"
sleep 2
warp-cli registration new --accept-tos 2>/dev/null || true
warp-cli mode proxy
warp-cli proxy port $PROXY_PORT
warp-cli connect
systemctl enable warp-svc --now

echo -e "${YELLOW}正在等待 WARP 建立隧道建立（大约需要 5 秒）...${NC}"
sleep 5

echo -e "${YELLOW}[4/6] 正在对本地 40000 端口进行 Google 回归测试...${NC}"
HTTP_STATUS=$(curl -x socks5h://127.0.0.1:$PROXY_PORT -sI https://www.google.com | grep -iE "HTTP/" | awk '{print $2}')

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}✓ 完美！WARP 本地代理网络测试成功，响应状态: 200${NC}"
else
    echo -e "${RED}❌ 警告: WARP 本地通道测试返回异常状态 [${HTTP_STATUS}]。${NC}"
fi

echo -e "${YELLOW}[5/6] 正在备份原 Xray 配置文件...${NC}"
cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"
echo -e "${GREEN}✓ 备份完成。备份文件保存在: ${CONFIG_PATH}.bak${NC}"

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

# 同时集成了 YouTube 和 Gemini 核心系列的域名池
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
    # 移除可能存在的旧规则，直接把最新规则顶到最前面
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

echo -e "${YELLOW}正在全力重启 Xray 服务...${NC}"
systemctl restart xray

if systemctl is-active --quiet xray; then
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 恭喜！全套自动化配置成功！YouTube & Gemini 分流全生效。${NC}"
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "${RED}❌ 警告: Xray 服务重启失败，请检查配置文件语法。${NC}"
fi
