#!/usr/bin/env bash

# =========================================================
# Xray WARP Socks5 分流解锁一键配置脚本
# 说明: 自动向 Xray 配置中添加 Socks5 出口及完整媒体/CDN 分流规则
# =========================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"
SOCKS5_PORT=40000

echo -e "${GREEN}==> 开始配置 Xray WARP 分流规则...${NC}"

# 1. 检查权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本！${NC}"
    exit 1
fi

# 2. 检查 Xray 配置文件是否存在
if [ ! -f "$XRAY_CONFIG" ]; then
    echo -e "${RED}错误: 未找到 Xray 配置文件 ($XRAY_CONFIG)${NC}"
    exit 1
fi

# 3. 检查系统 Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}未检测到 Python3，正在安装...${NC}"
    if command -v apt &> /dev/null; then
        apt update && apt install -y python3
    elif command -v yum &> /dev/null; then
        yum install -y python3
    else
        echo -e "${RED}错误: 无法自动安装 Python3，请手动安装后重试。${NC}"
        exit 1
    fi
fi

# 4. 使用 Python 注入配置
python3 - << 'EOF'
import json
import sys

config_path = "/usr/local/etc/xray/config.json"
socks_port = 40000

# 全量解锁域名清单（包含主站、API、核心 CDN）
target_domains = [
    # YouTube / Google Media CDN
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
    "domain:gstatic.com",
    # 可根据需要在此扩展其他平台（如 Netflix、Disney+ 等）
    # "geosite:netflix",
    # "geosite:disney"
]

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 1. 配置日志记录（方便查错）
    if "log" not in data:
        data["log"] = {}
    data["log"]["access"] = "/var/log/xray/access.log"
    data["log"]["loglevel"] = "info"

    # 2. 检查或添加 WARP Socks5 Outbound
    outbounds = data.get("outbounds", [])
    has_warp_out = False
    for out in outbounds:
        if out.get("tag") == "warp-out":
            has_warp_out = True
            # 更新端口
            out["settings"]["servers"][0]["port"] = socks_port
            break

    if not has_warp_out:
        outbounds.append({
            "tag": "warp-out",
            "protocol": "socks",
            "settings": {
                "servers": [
                    {
                        "address": "127.0.0.1",
                        "port": socks_port
                    }
                ]
            }
        })
    data["outbounds"] = outbounds

    # 3. 检查或添加 Routing Rule
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

    # 保存配置
    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print("✅ Xray 配置文件更新完成！")

except Exception as e:
    print(f"❌ 解析/修改配置文件失败: {str(e)}")
    sys.exit(1)
EOF

# 5. 配置验证与服务重启
echo -e "${GREEN}==> 正在验证 Xray 配置语法...${NC}"
if xray test -c "$XRAY_CONFIG"; then
    echo -e "${GREEN}==> 语法检查通过，重启 Xray 服务...${NC}"
    systemctl restart xray
    echo -e "${GREEN} SUCCESS: WARP 分流规则已生效！${NC}"
    echo -e "可以通过以下命令查看实时分流日志："
    echo -e "${YELLOW}tail -f /var/log/xray/access.log${NC}"
else
    echo -e "${RED}错误: Xray 配置文件存在语法错误，未能重启服务，请检查！${NC}"
    exit 1
fi
