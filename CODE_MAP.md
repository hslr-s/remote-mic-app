# 代码定位地图（Code Map）

本文件供 AI 助手快速定位代码。当你描述一个功能/需求时，先用「功能 → 源码位置」索引跳到对应文件，
再深入阅读，避免全仓扫描浪费 token。架构权威说明见 `DOCUMENTATION.md`、`TECHNICAL.md`、`AGENTS.md`。

> 产品名：英文 `SayAll`，中文「无线麦 SayAll」。macOS App，SwiftPM 构建，含 4 个可执行产物。

---

## 0. 顶层目录速查

| 目录/文件 | 作用 | 定位提示 |
| --- | --- | --- |
| `Sources/` | 全部 Swift/C/ObjC 源码（见 §1） | 改功能先看这里 |
| `Tests/RemoteMicTests/` | 单元测试（111 个 `.swift`，命名 `XxxTests.swift`） | 加/改功能同步补测试 |
| `feature/` | 各功能的公开产品规格与验收手册（`PRODUCT_SPEC.md`/测试手册） | 功能行为权威，改前必读 |
| `Testing/` | 跨功能测试手册、硬件契约（`HardwareCompatibilityContract.md` 等） | 验证边界 |
| `Resources/` | 图标、本地化字符串（`en.lproj`/`zh-Hans.lproj`）、Onboarding 图 | 文案/图标/本地化 |
| `scripts/` | 构建、打包、签名、公证、发布、治理校验脚本（49 个 `.sh`） | 发布/CI 流程 |
| `script/` | 仅 `build_and_run.sh`（本地一键构建运行） | 本地跑起来 |
| `packaging/` | entitlements、Info.plist 变体、HCI 服务 plist、豆包驱动、workbuddy | 打包资源 |
| `config/` | `release-assets.json`、`release-dependencies.json`（私有依赖版本钉） | 依赖版本 |
| `remote/` | 遥控器能力矩阵文档（规划用） | 硬件能力 |
| `Announcements/` | `hardware.json` 硬件公告数据 | 硬件公告 |
| `Bugs/` `Screenshots/` | 缺陷记录、视觉证据 | 不常改 |
| 根 `.md` | `AGENTS.md`(治理) `DOCUMENTATION.md`(入口) `TECHNICAL.md`(技术) `README.md` `BRANCH_MANAGEMENT.md` `FEATURE_DEVELOPMENT.md` `design-qa.md` `LOGGING.md` `RELEASING.md` `FILE_NAMING.md` | 流程/规范 |

---

## 1. 可执行产物与入口（Package.swift 定义）

| 产物 | 入口 | 职责 |
| --- | --- | --- |
| **RemoteMic**（主 App） | `Sources/RemoteMic/RemoteMicApp.swift` | 全部 UI、语音键、按键映射、设置、音频 |
| **SayAllMCP** | `Sources/SayAllMCP/main.swift` + `Sources/SayAllMCPKit/*` | 本地 MCP Server（Agent 访问），默认关闭，无需 Node.js |
| **AppleRemoteHCIService** | `Sources/AppleRemoteHCIService/main.swift` | 特权 Helper：底层蓝牙 HCI 协议（`AppleRemoteHCIProtocol`） |
| **AppleRemoteAudioCapture** | `Sources/AppleRemoteAudioCapture/main.swift` | 特权 Helper：远端音频采集（`AppleRemoteAudioCore`） |
| **AppleRemotePacketLogger** | 同 AudioCapture 目录的 `SayAllBTPacketLoggerClient.swift` | 蓝牙包日志客户端 |

### 模块依赖（公开边界）
- `AppleRemoteAudioCore/`（`AppleRemoteAudioCore.swift` `AppleRemoteAudioIPC.swift` `AppleRemoteXPCVoiceParser.swift`）
- `AppleRemoteHCIProtocol/`（`AppleRemoteHCIProtocol.swift` 协议定义）
- `AppleRemoteSupport/`（C，`AppleRemoteSupport.c`，IOKit/CoreFoundation）
- `AudioExceptionGuard/`（ObjC，`AudioExceptionGuard.m`，音频异常保护）
- `PublicRemoteCompatibility/`：`Core/RemoteCompatibility.swift` + `UI/WebRemoteSessionFallbackView.swift` —— **私有 MacRemote 包缺失时的公开兼容层**
- `SayAllMCPKit/`：MCP 服务实现（`SayAllMCPService` `SayAllMCPAuthorizationStore` `SayAllMCPHistoryStore` `SayAllMCPAuditLog` `SayAllMCPPaths` `SayAllMCPISO8601` `SayAllMCPIntegrationConfig`）
- 私有依赖（`sayall-private-platform` 等）通过环境变量注入，**不进本仓库**（见 `AGENTS.md` 私有依赖边界）。公开构建走 `PublicRemoteCompatibility` 兼容层。

---

## 2. Sources/RemoteMic 文件分组（按领域）

### 2.1 应用生命周期与入口
- `RemoteMicApp.swift` —— `@main` App 入口
- `RemoteMicRootView.swift` —— 根视图
- `AppEnvironmentSnapshot.swift` —— 环境快照（诊断用）
- `LoginItemService.swift` —— 登录项/开机启动
- `AppIconController.swift` `ApplicationIconResolver.swift` —— 应用图标解析与展示
- `AppLinks.swift` `SayAllDeepLink.swift` —— 深链/URL Scheme
- `ApplicationInstanceGuard.swift` —— 单实例保护

### 2.2 设置界面（Settings）
- `SettingsView.swift` `SettingsSidebarRow.swift` `SettingsNavigationStore.swift`
- `SettingsScreenshotRenderer.swift` —— 离屏截图渲染（design-qa 验证用）
- `SupplementalSettingsIntegration.swift` —— 私有/补充设置页接入
- `StatusItemPresentation.swift` —— 菜单栏图标状态

### 2.3 首次引导（Onboarding）
- `OnboardingView.swift` `OnboardingFlow.swift` `OnboardingScreenshotRenderer.swift`
- `OnboardingInputSourceSwitcher.swift`
- ⚠️ 改 Onboarding 必须先读 `feature/first-run-onboarding/PRODUCT_SPEC.md` 及平台附件

### 2.4 蓝牙 / 遥控器硬件
- `BluetoothLifecycle.swift` `NearbyRemoteLifecycle.swift` —— 蓝牙连接生命周期
- `RemoteDeviceIdentity.swift` `RemoteDeviceNamePolicy.swift` `RemoteDeviceNameReader.swift` —— 设备身份/命名
- `RemoteDeviceProfile.swift` `RemoteHardwareInput.swift` —— 设备档案/硬件输入
- `RemoteButtons.swift` `RemoteButtonInteraction.swift` `RemoteButtonInteractionSettings.swift`
- `RemoteButtonGestureRecognizer.swift` `RemoteButtonGestureLearning.swift` —— 手势学习
- `RemoteMappingCanvas.swift` —— 按键映射画布 UI
- `AppleSiriRemoteAdapter.swift` —— Siri Remote 适配器
- `XiaomiBluetoothBridge.swift` —— 小米遥控桥接
- `AppleRemoteHCIConfigurationClient.swift` —— 调 HCI 服务

### 2.5 语音键 / Fn 键
- `VoiceKeyMode.swift` —— 语音键模式（短按/长按/双击边界，受治理约束，**不得加双击/长按触发**）
- `VoiceFunctionKeyLatch.swift` `VoiceFnTapSessionController.swift`
- `RemoteVoiceFunctionMapper.swift` —— 语音功能键映射
- `VoiceInputCapabilityMatrix.swift` —— 输入能力矩阵
- `VoiceInputDestinationCoordinator.swift` —— 唤起目标后首次语音就绪协调
- `VoiceTargetActivityMonitor.swift` —— 目标活动监控
- `KeyboardHoldExecution.swift` —— 按住执行

### 2.6 HID / 键盘注入 / 快捷键
- `HIDRemoteMonitor.swift` `HIDRemoteScheduler.swift` `HIDReportRunLoop.swift` `HIDPrearmSession.swift` `HIDPermissionPoll.swift`
- `KeyboardInjector.swift` `KeyboardEventSuppressor.swift` `KeyboardShortcutPicker.swift`
- `EventTapPort.swift` `EventTapRunLoop.swift`
- `SystemKeyEventDecoder.swift` `RemoteNativeKeyMapper.swift`
- `ShortcutEventSequence.swift` `ShortcutCaptureMonitor.swift`
- `SecureInputMonitor.swift` —— 安全输入（密码框）监测
- `ScrollRegionInjector.swift` `ScrollRegionTarget.swift` —— 滚动区域翻页动作
- `ComposerFocusRequest.swift` `ComposerCaretTracker.swift` `SearchFocusRequest.swift` —— 输入框聚焦/光标

### 2.7 音频（Mac 本地）
- `MacMicrophoneCapture.swift` `MacMicrophoneSessionController.swift` `MacMicrophoneShortcut.swift` `MacMicrophoneVoiceKeyMonitor.swift`
- `AudioOutput.swift` `SystemAudioLifecycle.swift`
- `VirtualAudioLevelPolicy.swift` —— 虚拟麦克风电平策略
- `DoubaoAudioDevice.swift` —— 豆包输入法兼容音频设备
- `TestTone.swift` —— 测试音
- `AppleRemoteAudioClient.swift` —— 调 AudioCapture Helper

### 2.8 转写 / 录音资产
- `TranscriptCaptureCoordinator.swift` `TranscriptArchiveStore.swift`
- `TranscriptHistorySection.swift` `TranscriptAgentAccessSection.swift` `TranscriptAgentAccessModel.swift`
- `RecordingAssetStore.swift` —— 本地录音 M4A 资产
- `LocalUsageLedger.swift` —— 本地使用统计

### 2.9 通知 / UI 反馈
- `NoticeCenter.swift` `NoticeBubble.swift` `NoticeAnchor.swift` `NoticeHostAdapter.swift` `NoticeInline.swift`
- `OutputVolumeSlider.swift`

### 2.10 更新 / 版本中心
- `UpdateCheckCoordinator.swift` `UpdateInformationStore.swift` —— 关于页版本中心

### 2.11 诊断 / 日志
- `AppLogger.swift` —— 统一日志入口（遵循 `LOGGING.md`）
- `DiagnosticLogEnvelope.swift` `DiagnosticLogUploader.swift` `DiagnosticUploadTransport.swift`
- `PrivateDiagnosticUpload.swift` `PublicDiagnosticEvent.swift` `PublicDiagnosticEventStore.swift`
- `FirstUseDiagnostics.swift` `ATVVAudioDiagnostics.swift`
- `HardwareAnnouncementStore.swift`

### 2.12 配置 / 分享 / 迁移
- `AppSettings.swift` `AppSettingsPortableTransfer.swift` —— 设置与可携带配置迁移
- `MacConfigurationBackup.swift` —— 完整配置备份
- `AppSharing.swift` `MacAppSharing` 相关 —— 官网分享入口
- `BridgeAppModel.swift`

### 2.13 会员 / 私有功能集成
- `MembershipFeatureIntegration.swift` `MembershipFeatureTypes.swift`
- `PrivateFeatureIntegration.swift` `MacroFeatureIntegration.swift`
- `ChromecastFeatureIntegration.swift` `ChromecastFunctionKeyDrive.swift`
- `SiriRemoteFeatureIntegration.swift`
- `MCPClientIntegrationService.swift` `AgentConfigurationCommand.swift`
- `PhoneRemoteInvitationView.swift` `PhoneRemoteSessionState.swift` —— iPhone 二维码直连
- `PreferredInputSourceMonitor.swift` —— 首选输入法切换
- `PermissionStatusProbe.swift` —— 权限状态探测
- `AXSelfTargetPolicy.swift` —— 辅助功能自目标策略

### 2.14 按键映射 / 方案作用域
- `ButtonMappingSaveState.swift` `ButtonBindingConfiguration.swift`
- `ButtonProfileMacroRefreshPolicy.swift`
- （画布 UI 见 `RemoteMappingCanvas.swift`；作用域见 `feature/button-profile-scope/` `feature/mapping-scope-separation/`）

---

## 3. 功能 → 源码位置索引（开发新功能时优先查此表）

> 下表把 `feature/` 目录的功能名映射到 `Sources/RemoteMic` 中的实现文件。
> 完整行为与验收见对应 `feature/<name>/` 目录。

| 功能（feature 目录） | 关键源码文件 | 备注 |
| --- | --- | --- |
| `first-run-onboarding` 首次引导 | `OnboardingView` `OnboardingFlow` `OnboardingScreenshotRenderer` `OnboardingInputSourceSwitcher` | 改前必读 PRODUCT_SPEC |
| `button-mapping` 按键映射 | `RemoteMappingCanvas` `RemoteButtonInteraction` `RemoteButtons` `ButtonBindingConfiguration` `KeyboardShortcutPicker` `ShortcutCaptureMonitor` | |
| `button-profile-scope` 方案作用域 | `ButtonProfileMacroRefreshPolicy` + 私有 ButtonProfiles 包（公开仅适配层） | 私有实现不进仓 |
| `mapping-scope-separation` 作用域拆分 | `RemoteMappingCanvas` `ComposerFocusRequest` `ScrollRegion*` | |
| `mac-microphone-input` Mac 麦克风 | `MacMicrophoneCapture` `MacMicrophoneSessionController` `MacMicrophoneShortcut` `MacMicrophoneVoiceKeyMonitor` | |
| `common-phrases` 常用语 | 私有会员包（公开仅动作 ID/入口） | 公开构建不含实现 |
| `common-mac-shortcuts` 常用快捷键 | `KeyboardShortcutPicker` `KeyboardInjector` `EventTap*` | |
| `extended-voice-recording` 延长录音 | `VoiceKeyMode` `RemoteVoiceFunctionMapper` `VoiceFunctionKeyLatch` | MIC_EXTEND 方案已部分撤回 |
| `voice-input-destination-readiness` 语音就绪 | `VoiceInputDestinationCoordinator` `VoiceTargetActivityMonitor` | |
| `preferred-input-source-switching` 输入法切换 | `PreferredInputSourceMonitor` `OnboardingInputSourceSwitcher` | 豆包/微信输入法 |
| `scroll-region-page-actions` 滚动翻页 | `ScrollRegionInjector` `ScrollRegionTarget` | |
| `apple-watch-direct-remote` Watch 直连 | `NearbyRemoteLifecycle` `BluetoothLifecycle` 复用移动语音链路 | 等待真机 |
| `iphone-qr-direct` iPhone 二维码直连 | `PhoneRemoteInvitationView` `PhoneRemoteSessionState` | |
| `local-transcript-history` 本地转写 | `TranscriptCaptureCoordinator` `TranscriptArchiveStore` `TranscriptHistorySection` | 默认关闭 |
| `local-recording-assets` 本地录音 | `RecordingAssetStore` `MacMicrophoneCapture` | 默认关闭 |
| `sayall-mcp-integration` MCP | `Sources/SayAllMCP*` + `MCPClientIntegrationService` `AgentConfigurationCommand` | 默认关闭 |
| `quick-commands-private-integration` 组合动作 | 私有宏包（公开仅适配） | |
| `about-update-center` 版本中心 | `UpdateCheckCoordinator` `UpdateInformationStore` `SettingsView` | |
| `issue-feedback-link` 反馈入口 | `AppLinks`/关于页入口（测试见 `FeedbackLinkTests`） | |
| `mac-app-sharing` 官网分享 | `AppSharing` | |
| `installer-privacy-consent` 安装隐私 | 安装器（packaging）+ 策略 | 在 PKG 侧 |
| `encrypted-diagnostic-logs` 加密诊断 | `DiagnosticLogEnvelope` `DiagnosticLogUploader` `DiagnosticUploadTransport` `PrivateDiagnosticUpload` | |
| `cloudflare-download-cdn` CDN | 客户端更新源（appcast）+ `scripts/sync-update-feeds.mjs` | |
| `intel-ventura-release` Intel 发行 | `packaging/release-variants/intel.plist` + `RELEASE_VARIANT=intel` | |
| `reserved-shortcut-capture` 系统占用快捷键 | `ShortcutCaptureMonitor` `SecureInputMonitor` | |
| `first-use-success` 首用成功 | `FirstUseDiagnostics` + 安装器逻辑 | |
| `private-feature-integration` 私有集成 | `PrivateFeatureIntegration` `MembershipFeatureIntegration` `MacroFeatureIntegration` `ChromecastFeatureIntegration` `SiriRemoteFeatureIntegration` | |
| `mac-app-sharing` / `mac-microphone-input` 见上 | | |

---

## 4. 测试布局（Tests/）

- `Tests/RemoteMicTests/`：与源码 1:1 对应的 `XxxTests.swift`（如 `VoiceKeyModeTests` ↔ `VoiceKeyMode.swift`）。
- `Tests/Fixtures/` `Tests/SelfTest/`：测试夹具与自检。
- 关键测试类别：硬件契约（`*CapabilityContractTests`）、语音旅程（`CoreVoiceInputJourneyTests` `FirstVoiceReflectionJourneyTests` `WatchBluetoothVoiceJourneyTests`）、HID（`HID*`）、按键（`Button*` `RemoteButton*`）、音频恢复（`Audio*RecoveryTests`）、MCP（`SayAllMCP*` `MCPClientIntegrationServiceTests`）、Onboarding（`OnboardingFlowTests`）。

---

## 5. 资源与本地化（Resources/）

- `Resources/en.lproj/` 与 `Resources/zh-Hans.lproj/`：`Localizable.strings`（UI 文案）、`InfoPlist.strings`、`Glossary.md`（术语表）、`ReleaseHistory.md`、`FirstInstallGuide.md`、`DoubaoInputMethodCompatibility.md`。
- `Resources/AppIcons/` `Resources/Fonts/` `Resources/Onboarding/`（引导图）`Resources/AppIcon*.icns/png` `Resources/StatusIcon*.png`。
- 改文案：优先改两个 `Localizable.strings`；新增中文最小字号 12pt（见 `design-qa.md`）。

---

## 6. 打包与发布（scripts/ + packaging/）

| 脚本/资源 | 作用 |
| --- | --- |
| `scripts/build-app.sh` `script/build_and_run.sh` | 本地构建/运行 |
| `scripts/package-local-test-app.sh` | 本地测试包（SayAll.app，递增 CFBundleVersion） |
| `scripts/build-dmg.sh` `notarize-release.sh` | DMG / 公证 |
| `scripts/package-macos-release-in-actions.sh` `prepare-*-release.sh` `publish-*-release.sh` `stage-macos-preview.sh` | Preview/Stable 发布流水线 |
| `scripts/verify-*.sh` `*-test-*.sh` | 治理/发布校验（含 `verify-repository-governance.sh` 拒绝临时工具入库） |
| `scripts/sync-update-feeds.mjs` `release-assets.py` `prepare-private-platform.py` | 更新源/资产/私有依赖处理 |
| `packaging/app.entitlements` | 主 App 授权 |
| `packaging/release-variants/{apple-silicon,intel}.plist` | 架构变体 Info.plist |
| `packaging/apple-remote-hci/com.hd838a.SayAll.AppleRemoteHCIService.plist` | HCI Helper 启动项 |
| `packaging/doubao-driver/` `packaging/workbuddy/` | 豆包驱动、workbuddy |

---

## 7. 跨切面关注点（改代码时别漏）

- **日志**：统一走 `AppLogger`，遵循 `LOGGING.md`（脱敏、可关联、可归因）。
- **本地化**：新增文案进 `Resources/*/Localizable.strings`，中文 ≥12pt。
- **权限**：蓝牙/HID/辅助功能/麦克风状态用 `PermissionStatusProbe` `HIDPermissionPoll`。
- **私有边界**：私有实现不进仓；公开只留适配层（`*FeatureIntegration`）。改集成看 `feature/private-feature-integration/`。
- **语音键硬性约束**：`VoiceKeyMode` 不得引入双击/长按触发主语音；首字快、尾字全、正常不 flush（见 `AGENTS.md`）。
- **硬件契约**：新增硬件适配器须对照 `Testing/HardwareCompatibilityContract.md` 与 `HardwareVoiceAudioContract.md`。
- **规范门禁**：新功能必读 `FEATURE_DEVELOPMENT.md`；分支/提交看 `BRANCH_MANAGEMENT.md`；命名看 `FILE_NAMING.md`。
