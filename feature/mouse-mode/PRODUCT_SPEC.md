# 鼠标模式（Mouse Mode）产品规范

## 适用范围

本规范约束「鼠标模式」这一遥控器映射模式的产品行为、设置界面、运行时接管与兼容边界。
鼠标模式让用户用遥控器的方向键与确认/菜单键把 macOS 指针当鼠标操作：方向键步进移动指针，
确认键为左键、菜单键为右键、音量键为滚轮。它是一个可以开关的映射层，开启时替换本规范列出的
固定按键映射，其余按键保持原有（非鼠标模式）行为。

本功能属于「在现有按键映射体系上叠加一层模式」，不改动既有基础按键 / 自定义按键 / 系统媒体的
语义与数据，也不进入 `ButtonActionCategory` 的动作分类筛选（避免冲击作者的分类体系与回归测试）。

## 用户目标

- 用遥控器在没有实体鼠标时也能精确移动指针、点击、右键与滚动。
- 一键进入 / 退出鼠标模式；退出后仍可使用遥控器的全部常规功能。
- 进入模式后移动自然：单击走一步，按住越久移动越快（线性加速），松手即停，不引入长按识别。

## 范围（v1）

**包含：**

1. 全局单开关：开 / 关鼠标模式（默认关闭）。
2. 启用 / 退出键：用户在设置里选择「某个遥控按键 + 某个触发方式（单击 / 双击 / 长按）」作为
   模式切换键。该键在鼠标模式下**保留切换语义、不可被改映射成鼠标动作**（否则无法退出）。
3. 固定鼠标映射（v1 写死，编辑器中置灰只读）：
   - `up` / `down` / `left` / `right` → 鼠标指针向对应方向步进移动。
   - `ok`（中间确认键）→ 鼠标左键单击。
   - `menu`（底部菜单键）→ 鼠标右键单击。
   - `volumeUp` / `volumeDown` → 滚轮向上 / 向下；两者可通过「互换」开关对调（见下）。
4. 音量键滚轮方向互换（`volumeScrollInverted`）：仅音量 + / 音量 - 映射到滚轮上 / 下的方向可交换；
   方向键、确认键、菜单键的上下 / 左右**不互换、不可改**。
5. 移动行为：单击走一步（固定步进）；按住进入线性加速；松手即停。
6. 语音键：无论是否进入鼠标模式都保留语音语义，不可被改映射成鼠标动作，也不在鼠标模式编辑器中出现。
7. 未在本规范列出的其他遥控键（如 `power` / `home` / `back` / `tv` 等）：进入鼠标模式后**保持原有
   非鼠标模式绑定**（passthrough），不被本模式接管。
8. 设置页新增独立侧栏分区「鼠标模式」，不与动作分类筛选混用。
9. 复用既有 `SiriRemoteCursorFeedbackController` 做指针 / 滚轮的屏幕视觉反馈。

**不做（v1，留待 v2 独立计划）：**

- 不允许修改方向键 / 确认键 / 菜单键的鼠标映射（v1 写死）。
- 不开放「任意键映射到任意鼠标动作」的通用编辑器。
- 不区分不同遥控器型号的各套映射（v1 全局一套；v2 如需按型号再分层）。
- 不增加鼠标模式下的双击 / 长按手势（方向键在鼠标模式下只走「按=步进、按住=加速」）。

## 启用与退出

- 开关键由 `toggle: (button: RemoteButton, trigger: ButtonTrigger)` 描述，用户在设置中选择。
- 在任意状态下按下该「键 + 触发」即切换模式：关 → 开，开 → 关。
- 进入模式后该键继续承担切换职责，因此运行时**永远不对开关键套用鼠标映射**；编辑器中也禁止把
  开关键从「切换」改走。
- 语音键走既有语音路径，绕过本模式（见「锁定约束」）。

## 默认映射表

| 遥控键 | 鼠标动作 | v1 是否可改 |
| --- | --- | --- |
| `up` | 指针向上移动一步 | 不可改（置灰） |
| `down` | 指针向下移动一步 | 不可改（置灰） |
| `left` | 指针向左移动一步 | 不可改（置灰） |
| `right` | 指针向右移动一步 | 不可改（置灰） |
| `ok` | 鼠标左键单击 | 不可改（置灰） |
| `menu` | 鼠标右键单击 | 不可改（置灰） |
| `volumeUp` | 滚轮向上（受 `volumeScrollInverted` 影响可变为向下） | 仅方向可互换 |
| `volumeDown` | 滚轮向下（受 `volumeScrollInverted` 影响可变为向上） | 仅方向可互换 |
| 其他键 | 保持原非鼠标模式绑定 | passthrough，不在本模式编辑 |

对应新增 `ButtonAction` 枚举值：`mouseMoveUp` / `mouseMoveDown` / `mouseMoveLeft` / `mouseMoveRight` /
`mouseLeftClick` / `mouseRightClick` / `mouseScrollUp` / `mouseScrollDown`。这些值是 `ButtonAction` 的
追加项，保持 `String` rawValue 以便向前 / 向后兼容（旧版本读不懂的 case 走既有
`MappingHostBindingCodec` 丢弃，不崩溃）。

## 移动行为（步进 + 线性加速）

- 单个方向键**单击**（按下后快速松开、未超过按住阈值）：指针沿该方向走 **一个 baseStep**（像素）。
- 方向键**按住**（按下后不松开）：先立即走一个 baseStep，超过约 250ms 后启动加速定时器，
  每 `stepInterval` 毫秒沿同方向移动一次，单次位移从 baseStep 线性增加到
  `min(maxStep, baseStep + accel * 已加速次数)`，直到 `maxStep` 封顶。
- **不进入长按识别窗口**：按住直接被当作「加速移动」，不使用单击 / 双击 / 长按手势判定，
  松手立即停。这与 `AGENTS.md` 的语音键约束无关（语音键不在本模式内）。
- 默认加速参数（可在设置中调整，属可调参数而非行为开关）：
  `baseStep = 8`、`accel = 4`（像素 / 每 100ms）、`maxStep = 60`、`stepInterval = 60`（ms）。
- 松开、断连、休眠、权限撤销、方案 / 前台目标切换、退出鼠标模式：必须立即结束加速并抬起所有
  按住的移动键，指针不得停留在持续移动状态。

## 锁定约束

- **开关键锁定**：鼠标模式的开关键在编辑器内不可被改映射；运行时开关键始终执行模式切换。
- **语音键锁定**：语音键始终走语音路径，不进入鼠标映射，也不在编辑器中出现。
- **固定键置灰**：方向键 / 确认键 / 菜单键在编辑器内显示为锁定只读，明确标注「v2 可自定义」。

## 设置界面（独立侧栏分区）

- 入口：设置页侧栏新增「鼠标模式」分区，独立右侧栏项，不进入 `ButtonActionCategory` 筛选。
- 暴露控件（v1）：
  1. 启用开关（全局）。
  2. 开关键选择：选择「遥控键 + 触发方式」。
  3. 音量滚轮互换开关（`volumeScrollInverted`）。
  4. 加速参数：baseStep / accel / maxStep / stepInterval（带合法范围与步长，输入越界回退默认）。
  5. 固定映射只读展示：方向 / 确认 / 菜单 的映射以锁定样式显示，并说明「v2 可改」。
- 不在本分区编辑语音键与开关键的映射；其他键不显示（保持原绑定）。
- UI 文案改动遵循 `design-qa.md`（中文 ≥ 12pt、优先页面内完成、不堆长下拉）。

## 运行时接管（薄插入，零默认影响）

- 新增 `MouseModeController` 持有 `isActive`、当前 `toggle` 与 `volumeScrollInverted` / 加速参数；
  提供 `resolve(button, trigger) -> ConfiguredButtonAction?` 与 `beginHold(button)` / `endHold(button)`。
- 在 `HIDRemoteMonitor` 注入一个**默认返回 nil 的可选闭包** `mouseModeResolver`：仅当非 nil 且
  鼠标模式激活时，先于普通绑定解析走鼠标映射；语音键与开关键强制走原路径；其他未接管键 passthrough。
  对共享派发文件的 diff 保持最小、机械，便于作者整体采纳或丢弃。
- `enabled = false` 时整条链路 passthrough，稳定行为零变化。
- `MouseInjector` 用 `CGEvent` 发出 `kCGEventMouseMoved` / 左右键 `Down`·`Up` / `kCGEventScrollWheel`；
  移动时调用既有 `SiriRemoteCursorFeedbackController.handle(.pointerMoved(speed:))` 做视觉反馈，
  滚轮时调用 `.scrolled(pixels:speed:)`。

## 源码位置索引

| 职责 | 文件 |
| --- | --- |
| 配置模型 `MouseModeConfiguration` / 固定映射 `MouseModeDefaults` | `Sources/RemoteMic/MouseModeConfiguration.swift` |
| CGEvent 注入内核 | `Sources/RemoteMic/MouseInjector.swift` |
| 模式状态机 + 解析 + 加速 | `Sources/RemoteMic/MouseModeController.swift` |
| 设置分区 UI | `Sources/RemoteMic/MouseModeSettingsView.swift` |
| 追加鼠标动作枚举 | `Sources/RemoteMic/RemoteButtons.swift`（`ButtonAction`） |
| 运行时薄 hook | `Sources/RemoteMic/HIDRemoteMonitor.swift`（`mouseModeResolver`） |
| 本地化 | `Resources/en.lproj/Localizable.strings`、`Resources/zh-Hans.lproj/Localizable.strings` |
| 单元测试 | `Tests/RemoteMicTests/MouseModeTests.swift` |
| 测试手册 | `feature/mouse-mode/testing.md` |

## 与作者原功能合并的兼容预留

1. 所有新增放独立文件（`MouseMode*`），共享文件只加一个默认 nil 的可选 hook，diff 机械、可整段丢弃。
2. **不复用** `RemoteButtonInteractionSettings.modes` 字段（作者用来存「按住模式」），鼠标模式用
   独立 `AppSettings` key 且结构可版本化。
3. `ButtonAction` 用 `String` rawValue 枚举追加新 case；不改 `ButtonActionCategory` 现有集合，
   保住 `SettingsView` 筛选回归测试。
4. 鼠标模式作为独立侧栏分区，不进动作分类筛选，避免冲击作者未来的分类体系。
5. 默认关闭；`enabled = false` 时整条链路 passthrough，稳定行为零变化，便于上游选择性采纳。
6. 配置 schema 单独、可版本化，导入导出可被作者按需合并；v2 扩展只加可选 `bindings` 覆盖字典，
   运行时 `resolve` 优先读覆盖、否则回退 `MouseModeDefaults`，结构零改动。

## 日志与隐私

- 统一走 `AppLogger`，覆盖「请求入口 → 最终用户结果」链路：模式切换、按键解析命中、注入结果
  （成功 / 失败 / 权限缺失）。
- 脱敏：不记录指针坐标、窗口标题、第三方 App 内容；外部状态未知时记 `unknown` 而非推测。

## 验证边界

- 自动化：覆盖模式切换、固定映射解析、音量互换、加速步进与封顶、松手 / 断连立即停止、passthrough
  其他键、默认关闭零影响。
- 本机代理：在 `scripts/package-local-test-app.sh` 的 `public` 模式构建并启动验证。
- 真实环境：需真实遥控器 / 蓝牙 / 辅助功能权限才能验收实际指针移动与点击；无实机证据时标记待验证。
- UI 变更：按 `FEATURE_DEVELOPMENT.md` 的截图门禁，PR 附实际运行截图（中文浅色 / 深色、最小尺寸）。

## 不做事项的后续

- v2（独立计划 / 独立分支）：开放方向 / 确认 / 菜单键的鼠标映射编辑（模型加 `bindings` 覆盖字典）；
  评估是否按遥控器型号分层；评估是否引入鼠标模式下的双击 / 长按手势。
