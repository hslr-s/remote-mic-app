# 构建、运行与调试（开发者）

本文件面向想从源码把「无线麦 SayAll」跑起来、断点调试或本地验证的开发者。普通用户请看 [README.md](README.md)；技术架构见 [TECHNICAL.md](TECHNICAL.md)；给 AI 客户端配 MCP 见 [AI_SETUP.md](AI_SETUP.md)。

> 改动代码、提交或开 PR 前，必须先读 [AGENTS.md](AGENTS.md) 与 [BRANCH_MANAGEMENT.md](BRANCH_MANAGEMENT.md)。

## 1. 环境要求

- Apple Silicon Mac（macOS 14+）或 Intel Mac（macOS 13+）；
- Xcode 或 Command Line Tools，提供 Swift 6.2+ 工具链（`xcode-select --install`）；
- 不需要任何私有仓库权限；默认公开模式即可编译运行；
- 想验证真实语音/按键，需要小米蓝牙遥控器 2 / 2 Pro，以及回环音频设备（`MiRemoteV 2ch` 或 BlackHole 2ch）。公开开发构建不含驱动，驱动需从官网 Releases 的 Installer PKG 单独安装。

## 2. 公开模式构建并运行

公开开发自用模式会 release 构建、递增本机构建号、ad-hoc（或 Developer ID）签名，安装到 `~/Applications/SayAll.app` 并自动启动：

```bash
cd /Users/sunjingliang/my_code/remote-mic-app
SAYALL_PRIVATE_PLATFORM_MODE=public ./scripts/package-local-test-app.sh
```

只构建安装、不自动启动（便于自己在 Xcode / Finder 打开）：

```bash
SAYALL_LOCAL_DEFER_LAUNCH=1 SAYALL_PRIVATE_PLATFORM_MODE=public ./scripts/package-local-test-app.sh
```

启动后默认打开设置面板；菜单栏 / Dock 行为由发布 `Info.plist` 的 `LSUIElement` 等键决定，本地包同样遵循。

## 3. 用 Xcode 图形化调试

SwiftPM 工程可直接用 Xcode 打开，支持断点、View Inspector、变量查看：

```bash
xed .        # 等价 open Package.swift -a Xcode
```

打开后在 scheme 选择器选 **RemoteMic**（即 `SayAll.app` 可执行 target）直接 Run。注意：Xcode 调试运行不会带发布 PKG 注入的完整 `Info.plist` 键（如 `LSUIElement`、Sparkle 配置），菜单栏 / 无 Dock 行为与自动更新在调试态会有差异，但不影响主流程断点调试。

## 4. 测试

SwiftPM 在本地运行必须带 `--disable-keychain`（见 [AGENTS.md](AGENTS.md) 的 SwiftPM 本地凭据边界）：

```bash
xcrun swift test --disable-keychain
./scripts/test.sh        # 协议/策略自检 + 完整应用编译
```

## 5. 日志与排障

运行时日志（由应用自身写入，不含语音内容、蓝牙地址或个人路径）：

```bash
tail -f ~/Library/Logs/RemoteMic/runtime.log
```

首次运行若连不上遥控器或按键无反应，先到「系统设置 → 隐私与安全性」确认已授予：**蓝牙**、**输入监控**、**辅助功能**；改权限后完全退出再重开 App。蓝牙配对：同时长按遥控器「主页 + 菜单」进入配对，连接名为 `MI RC` / `Xiaomi Bluetooth Remote 2 Pro` / `Xiaomi Bluetooth Remote 2` / “小米蓝牙语音遥控器”的设备。

## 6. 兼容边界与验证状态

- 公开模式（`SAYALL_PRIVATE_PLATFORM_MODE=public`）不含私有会员功能：常用语、Siri Remote 会员能力不会启用，也不解析私有依赖；缺少私有组件时应用必须仍能启动（见 AGENTS.md 私有依赖边界）。
- 不设置任何私有包路径时，`Package.swift` 会自动走公开兼容层；显式设置 `public` 模式可避免误走 `required` 集成路径。
- 真实遥控器、系统权限弹窗、蓝牙配对、辅助功能授权、回环音频设备与第三方语音工具的文字上屏属于真实环境验收，自动化测试、单元测试与构建通过不能替代。
- 向他人分发的安装包按 [RELEASING.md](RELEASING.md) 执行 Developer ID 签名与 Apple 公证门禁；本地公开构建仅供本机开发自用。
