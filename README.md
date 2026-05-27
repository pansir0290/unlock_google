# ⚡ CF WARP + Xray (YouTube & Gemini) 全自动精准分流脚本

[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange.svg)](https://www.debian.org/)
[![Xray](https://img.shields.io/badge/Xray--core-1.8.0+-blue.svg)](https://github.com/XTLS/Xray-core)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

这是一个专为 `Ubuntu / Debian` 系统设计的全自动一键分流脚本。它可以安全、**绝对无损**地为现有的 Xray 节点服务注入 Cloudflare WARP 出站规则，完美解决 **YouTube Premium 不显会员（送中）** 以及 **Google Gemini 区域限制（如香港 IP 提示不支持）** 的痛点。

---

## ✨ 核心特性

* 🛡️ **安全无损注入**：拒绝粗暴的覆盖！脚本调用系统 Python 动态解析并重写 JSON 树结构，**绝不破坏、不删除**你原有配置中的任何已有节点或老规则。
* 🔙 **自动双重备份**：每次运行前，自动在同目录下生成 `.bak` 备份文件。自带“后悔药”机制，随时一键还原。
* 🧠 **双重完美分流**：
  * **YouTube 模块**：集成 YouTube 网页端、移动端 App、视频流（googlevideo）及核心 API。
  * **Gemini 模块**：集成 Gemini 网页主站、Google AI Studio、底层 API，以及手机端助理切换所需的**隐藏后端域名**。
* 🩹 **智能 DNS 净化**：强制覆盖系统临时 DNS 为 `8.8.8.8`，彻底规避部分 VPS 商家自带的流媒体解锁 DNS 导致 WARP 无法握手、网络卡死的死循环。
* 🚀 **官方原生内核**：采用 Cloudflare WARP 官方最新原版客户端（非第三方简陋内核），自动注册并配置为最稳定的本地 Socks5 代理模式（端口 `40000`）。

---

## 📋 适用条件与环境

* **操作系统**：Ubuntu / Debian (Root 用户或具有 sudo 权限)。
* **依赖前提**：机器上必须已经提前安装并运行着 Xray 服务。
* **默认路径**：Xray 配置文件默认存放在 `/usr/local/etc/xray/config.json`。

---

## 🚀 一键安装与运行

直接登录你的 VPS 终端（Root 权限），复制并执行以下单行命令：

```bash
curl -sSL https://raw.githubusercontent.com/pansir0290/unlock_google/main/unlock.sh | bash

