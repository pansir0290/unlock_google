#!/usr/bin/env bash

# =================================================================
# Xray WARP Socks5 一键自动部署与精确分流脚本 (方案B 整合版)
# 说明: 自动检测/安装 WARP Socks5 (端口 40000) + 自动注入 Xray 全量分流
# =================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"
SOCKS5_PORT=40000

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}    Xray WARP Socks5 一键部署与分流注入脚本         ${NC}"
echo -e "${GREEN}====================================================${NC}"

# 1. 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本！${NC}"
    exit 1
fi

# 2. 检查 Xray 配置文件是否存在
if [ ! -f "$XRAY_CONFIG" ]; then
    echo -e "${RED}错误: 未找到 Xray 配置文件 ($XRAY_CONFIG)，请先安装 Xray！${NC}"
    exit 1
fi

# 3. 检查系统基础依赖 (curl & python3)
echo -e "${GREEN}==> 1/3 检查基础依赖环境...${NC}"
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}未检测到 curl，正在安装...${NC}"
    apt-get update && apt-get install -y curl || yum install -y curl
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}未检测到 python3，正在安装...${NC}"
    apt-get update && apt-get install -y python3 || yum install -y python3
fi

# 4. 检测或自动安装 WARP Socks5
echo -e "${GREEN}==> 2/3 检测 127.0.0.1:${SOCKS5_PORT} WARP 代理状态...${NC}"

check_warp() {
    curl -s --socks5 127.0.0.1:${SOCKS5_PORT} --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"
}

if check_warp; then
    echo -e "${GREEN}✅ 检测到 WARP Socks5 代理在端口 ${SOCKS5_PORT} 上正常运行！${NC}"
else
    echo -e "${YELLOW}⚠️ 端口 ${SOCKS5_PORT} 未正常响应 WARP 代理服务，开始静默安装 WARP...${NC}"
    
    # 使用 fscarmen WARP 官方非交互模式安装 WireGuard / Socks5 代理 (指定端口 40000，IPv4+IPv6 双栈)
    bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) s 5 ${SOCKS5_PORT}
    
    # 再次验证
    sleep 3
    if check_warp; then
        echo -e "${GREEN}✅ WARP Socks5 代理安装成功并已就绪！${NC}"
    else
        echo -e "${RED}❌ WARP 安装完成但检测超时，请手动运行 'curl -x socks5://127.0.0.1:${SOCKS5_PORT} https://www.youtube.com -I' 查验。${NC}"
        # 允许继续注入规则，便于后续调试
    fi
fi

# 5. 使用 Python 注入 Xray 配置
echo -e "${GREEN}==> 3/3 注入 Xray 路由规则与 Socks5 出口配置...${NC}"

python3 - << 'EOF'
import json
import sys

config_path = "/usr/local/etc/xray/config.json"
socks_port = 40000

# 全量解锁域名清单（包含主站、API、媒体 CDN，彻底解决视频转圈/卡顿）
target_domains = [
    "domain:youtube.com",
    "domain:youtube-nocookie.com",
    "domain:youtu.be",
    "domain:yt.be",
    "domain:ytimg.com",
    "domain:ggpht.com",
    "domain:googlevideo.com",
    "domain:youtubeeducation.com",
    "domain:youtubekids.com",
    "domain:googleapis.com",
    "domain:gstatic.com"
]

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 1. 开启 Access 日志便于分流排查
    if "log" not in data:
        data["log"] = {}
    data["log"]["access"] = "/var/log/xray/access.log"
    data["log"]["loglevel"] = "info"

    # 2. 检查或更新 Outbound (warp-out)
    outbounds = data.get("outbounds", [])
    has_warp_out = False
    for out in outbounds:
        if out.get("tag") == "warp-out":
            has_warp_out = True
            out["protocol"] = "socks"
            out["settings"] = {
                "servers": [{"address": "127.0.0.1", "port": socks_port}]
            }
            break

    if not has_warp_out:
        outbounds.append({
            "tag": "warp-out",
            "protocol": "socks",
            "settings": {
                "servers": [{"address": "127.0.0.1", "port": socks_port}]
            }
        })
    data["outbounds"] = outbounds

    # 3. 检查或更新 Routing Rules (确保优先插入第一条)
    routing = data.get("routing", {})
    rules = routing.get("rules", [])
    has_warp_rule = False

    for rule in rules:
        if rule.get("outboundTag") == "warp-out":
            has_warp_rule = True
            rule["domain"] = target_domains
            break

    if not has_warp_rule:
        rules.insert(0, {
            "type": "field",
            "outboundTag": "warp-out",
            "domain": target_domains
        })

    data["routing"]["rules"] = rules

    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print("✅ Xray 配置文件解析并更新成功！")

except Exception as e:
    print(f"❌ 解析/修改配置文件失败: {str(e)}")
    sys.exit(1)
EOF

# 6. 配置语法验证与服务重启
echo -e "${GREEN}==> 正在验证 Xray 配置语法...${NC}"
if xray test -c "$XRAY_CONFIG"; then
    echo -e "${GREEN}==> 语法检查通过，正在重启 Xray 服务...${NC}"
    systemctl restart xray
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN} SUCCESS: WARP 安装与 Xray 分流设置全部完成！${NC}"
    echo -e "可通过以下命令实时查看分流日志："
    echo -e "${YELLOW}tail -f /var/log/xray/access.log${NC}"
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "${RED}错误: Xray 配置文件存在语法错误，未能重启服务，请手动排查！${NC}"
    exit 1
fi
