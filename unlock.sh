cat << 'EOF' > update_warp_route.py
import json
import os

# 1. 锁死 Xray 正在实际加载的真实配置文件路径
cfg_path = "/usr/local/etc/xray/config.json"

if not os.path.exists(cfg_path):
    print(f"❌ 错误: 未找到 Xray 配置文件: {cfg_path}")
    exit(1)

# 2. 读取现有配置
with open(cfg_path, 'r', encoding='utf-8') as f:
    try:
        data = json.load(f)
    except Exception as e:
        print(f"❌ JSON 解析失败，请检查配置文件格式: {e}")
        exit(1)

# 3. 自动备份
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

# 确保 routing 存在并设置全局域名解析策略
if "routing" not in data: 
    data["routing"] = {}
data["routing"]["domainStrategy"] = "IPOnDemand"

if "rules" not in data["routing"]: 
    data["routing"]["rules"] = []

# 清理旧的 WARP 分流规则，防止重复累加
data["routing"]["rules"] = [
    r for r in data["routing"]["rules"] 
    if r.get("outboundTag") != outbound_tag
]

# 4. 插入显式域名规则（解决缺少 geosite.dat 或 CDN 域名漏网问题）
youtube_rule = {
    "type": "field",
    "outboundTag": outbound_tag,
    "domain": [
        "domain:youtube.com",
        "domain:googlevideo.com",
        "domain:ytimg.com",
        "domain:youtu.be",
        "domain:yt.be",
        "geosite:youtube"
    ]
}

data["routing"]["rules"].insert(0, youtube_rule)

# 5. 安全回写配置
with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"🎯 策略无损注入成功！配置已同步至: {cfg_path}")
print(f"📦 备份文件已生成至: {backup_path}")
EOF

# 运行 Python 脚本写入配置
python3 update_warp_route.py

# 验证配置并重启服务
echo "🔄 正在校验并重启 Xray 服务..."
if xray run -test -config /usr/local/etc/xray/config.json && systemctl restart xray; then
    echo "========================================================"
    echo "🎉 YouTube 精准分流自动化配置已成功生效！"
    echo "👉 所有 YouTube 网页及视频流 (googlevideo) 已强行走 40000 端口 WARP 出口。"
    echo "========================================================"
else
    echo "❌ 警告: 写入成功，但 Xray 重启失败，正在尝试恢复备份..."
    cp /usr/local/etc/xray/config.json.bak /usr/local/etc/xray/config.json
    systemctl restart xray
    exit 1
fi
