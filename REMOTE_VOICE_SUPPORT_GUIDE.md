# 遥控器语音支持识别指南

本文档用于判断一款"带语音按键的蓝牙遥控器"是否可以被「无线麦 SayAll」(Remote Mic) 当作无线麦克风使用，以及在动手接入前如何低成本地确认可行性。

本项目的蓝牙连接分两条技术路线，识别方法也据此展开：

- **路线 A — 苹果 Siri 遥控器**：底层抓包（HCI tap）。通过 root 辅助程序向系统蓝牙守护进程写入调试配置、订阅苹果私有 `com.apple.bluetooth.BTPacketLogger` XPC 服务，抓取蓝牙控制器原始包再抠出 Opus 音频。详见 `Sources/AppleRemoteHCIService/`、`Sources/AppleRemoteAudioCapture/`、`Sources/AppleRemoteAudioCore/`。
- **路线 B — 小米等安卓电视语音遥控器**：标准 `CoreBluetooth` + ATVV 语音协议（服务 UUID `AB5E0001-5A21-4F05-BC7D-AF01F617B664`）。详见 `Sources/RemoteMic/XiaomiBluetoothBridge.swift`、`Sources/RemoteMic/ATVVProtocol.swift`。

普通用户买的"空中飞鼠 / 智能语音遥控"大多属于路线 B 的范畴，或根本不通过蓝牙传音频。

---

## 核心判断标准

能否用作无线麦，只取决于一件事：**这个遥控器的麦克风能不能通过蓝牙把音频发出来。**

- ✅ 支持：遥控器自带麦克风，且通过 BLE 标准语音协议（如 ATVV）或经典蓝牙 HFP 把音频发出。
- ❌ 不支持：纯按键遥控（无麦克风）、只有 HID 按键通道、或麦克风音频走私有/加密且无法拿到的协议。

> ⚠️ 关键坑：大量廉价"空中飞鼠"的语音只在 **2.4G USB 接收器模式** 下有效。接收器插上后被识别成"USB 声卡 + HID 键盘"，麦克风走 USB，不走蓝牙。这类设备在**蓝牙模式下通常没有麦克风**，但插接收器时 Mac 会把它当成普通 USB 麦克风直接使用，无需本项目。

---

## 识别步骤（按成本从低到高）

### 第 1 步：问客服 / 看商品页（无需购买）

向卖家确认一句话：

> "蓝牙模式下麦克风能用吗？还是只有插 2.4G 接收器才有麦克风？"

同时记录商品型号（如 iPazzPort X9、KP-810 系列等），并查官方说明书（如 manuals.plus 上的型号手册），确认"语音搜索"的实现方式（谷歌语音通常绑定 2.4G 接收器）。

若客服明确"蓝牙模式语音无反应"或"语音需配接收器"，基本可判定蓝牙桥接路线走不通。

### 第 2 步：拿到设备后做决定性验证（蓝牙配对到 Mac）

1. **看系统是否原生识别为麦克风**
   配对后打开"系统设置 → 声音 → 输入"，看是否出现遥控器对应的麦克风。
   - 出现 → 说明蓝牙走 HFP（免提协议），macOS 原生即可当麦克风，甚至无需本项目。
   - 不出现 → 继续下一步。

2. **看暴露的蓝牙服务**
   终端执行：
   ```sh
   system_profiler SPBluetoothDataType
   ```
   若服务里只有 HID（键盘/鼠标），无任何音频服务，说明蓝牙模式无麦。

3. **扫描是否含 ATVV 语音服务**
   用 nRF Connect（macOS 或 Android 手机均可）扫描该设备广播的服务，检查是否存在：
   ```
   AB5E0001-5A21-4F05-BC7D-AF01F617B664
   ```
   - 存在 → 与小米遥控器同协议，理论上可写 bridge 适配进本项目。
   - 不存在且第 1、2 步也无音频证据 → 蓝牙模式不支持语音。

### 第 3 步：即使协议对上，也需要在 App 内"上户口"

本项目的采纳逻辑**只按已知型号白名单识别**，不靠协议本身。相关代码：

- `Sources/RemoteMic/BluetoothLifecycle.swift` 中的 `XiaomiVoiceRemoteNameMatcher`、`ForeignVoiceRemoteProduct`、`VoiceRemoteAdmission`。
- 未列入白名单的 ATVV 设备会被 `rejectUnrecognizedName` / `rejectUnnamed` 明确拒绝（防止套用错误型号的图与按键布局）。

因此，确认协议后还需新增一个型号档案（名字白名单 + 编码格式 + 按键映射），这是一次正式的开发任务，并按仓库 `Testing/HardwareCompatibilityContract.md` 完成实机验证，不能随意把陌生设备改成"已连接"。

---

## 三种可能结局对照

| 验证结果 | 结论 |
|---|---|
| 蓝牙模式有麦（HFP 或 ATVV） | HFP → 系统原生可用；ATVV → 新增型号档案后可接入本项目 |
| 仅 2.4G 模式有麦 | 插接收器后 Mac 当作**普通 USB 麦克风**，无需本项目；蓝牙遥控路线不通 |
| 纯按键、蓝牙无任何音频 | 不支持语音，仅能当键鼠 |

---

## 建议流程小结

1. 先问客服确认蓝牙模式是否含麦克风，再决定是否购买。
2. 若只有 2.4G 有麦，你的"拿遥控器当无线麦"需求其实直接插接收器就能满足（Mac 原生识别为 USB 麦克风）。
3. 若想要本项目式的"蓝牙连接 + 语音键会话管理 + 文字上屏"完整体验，则必须蓝牙模式真的传音频；确认后按型号档案 + `HardwareCompatibilityContract` 实机验收接入。
