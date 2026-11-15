# 自定义模式（Custom Modes）产品规范

## 目标

把「普通模式 / 鼠标模式」扩展为可创建的任意多模式：每个自定义模式持有独立的一套按键映射，
进入方式与其他动作一样在**按键映射页**绑定——和「切换鼠标模式」完全同一套机制。
预设的鼠标模式行为完全不变。

## 范围与非目标

- 自定义模式是**纯按键映射切换**：不提供鼠标模式的指针移动/加速/滚动，不接管方向键边沿。
- 切换模式的入口是 `ButtonAction.customModeToggle` 动作，配在按键映射页，
  目标模式 ID 由 `ConfiguredButtonAction.modeID` 携带。
- 鼠标模式保持现状，与自定义模式互斥（进入任一侧都会先退出另一侧）。
- 不做配置导出/导入：自定义模式与切换目标使用独立 UserDefaults 键 `customModeConfiguration`，
  不参与配置导出；导出普通映射时若遇到 `customModeToggle` 会降级为 disabled，避免脏数据。
- 只有 Siri Remote（HIDRemoteMonitor）路径分发切换动作；Apple Remote / Chromecast / 手机端
  与其他鼠标动作一致，不接管（该动作会被键盘注入路径忽略，不会误注入按键）。

## 数据模型

- `CustomMode`：`id`、`name`、`showsIndicator`、`indicatorColorHex`（nil=跟随系统强调色）、
  `bindings`（稀疏绑定表）。没有切换键字段——切换动作配在普通映射页。
- `CustomModeConfiguration`：模式数组，整体 JSON 编解码，旧字段缺失时取默认值。
- `ConfiguredButtonAction` 新增 `modeID: UUID?`，仅 `action == .customModeToggle` 时有效；
  可选字段使旧配置 JSON 编解码兼容。
- 「普通模式」即按键映射页的常规映射，不在本模型中。

## 解析与运行时

1. **统一动作来源**：`HIDRemoteMonitor.performConfiguredAction` 按优先级取
   模式内绑定 > 手势捕获 > 映射页普通绑定，得到唯一 `configured`，
   后续所有动作只依据这一份判定（与既有「映射页配什么就做什么」一致）。
2. **切换动作**：`configured.action == .customModeToggle` 时，读 `configured.modeID`，
   先 `MouseModeController.setActive(false)` 再 `CustomModeController.toggle(modeID:)`；
   modeID 缺失（模式被删）时记日志并吞掉，不切换。
3. **进入/退出**：按配置了切换动作的键进入目标模式；再按同一次键退出回普通模式；
   按绑定了其他目标模式的切换键直接切过去。
4. **模式内映射**：激活模式下，槽位在绑定表中的条目覆盖普通映射；
   未设置的槽位继续走普通映射（回退语义）。
5. **互斥**：进入鼠标模式（`.mouseModeToggle`）前 `CustomModeController.deactivate`；
   进入自定义模式前 `MouseModeController.setActive(false)`。
6. **指示圈**：`showsIndicator` 开启时进入模式即在光标位置显示常驻彩色圈
   （复用 `SiriRemoteCursorFeedbackController` 的 pin + ringColor）；
   退出或关闭时解除 pin。鼠标模式反馈圈实例独立。
7. **激活模式被删除**时立即退出（`apply(configuration:)` 保证）。
8. **日志**：`CUSTOM MODE phase=toggle/state/action` 脱敏日志，不含坐标与窗口标题。

## 设置页

### 按键映射页（切换入口）

- 动作网格新增「切换自定义模式」（归在 `systemAndMedia`，与「切换鼠标模式」同组）。
- 选中该动作后展开「目标模式」网格，列出所有自定义模式（带指示色圆点）；
  选中写入 `configured.modeID`，槽位摘要显示「切换到：<模式名>」。
- 无模式时显示引导去「自定义模式」页新建；目标模式被删时显示橙色提示。

### 自定义模式页（侧栏，位于 privateFeature 之后、about 之前）

- 模式列表：横向 chip，含指示色圆点；输入名称新建；可删除、改名。
- 模式指示圈：显示开关、6 色预设色板、自定义 ColorPicker、跟随系统按钮。
- 模式内按键映射：复用遥控器画布；槽位摘要显示本模式动作或
  「普通：<普通映射动作>」；点击槽位弹出动作选择 Sheet
  （排除需要额外载荷的动作，以及两个切换动作——它们只配在普通映射页）。

## 默认与兼容

- 默认无自定义模式；所有行为与此前一致（未激活完全 passthrough）。
- 旧配置无 `customModeConfiguration` 键 → 空列表；JSON 缺字段 → 默认值。
- `ConfiguredButtonAction` 新增可选 `modeID` 字段，旧映射 JSON 缺字段解码为 nil。
- 侧栏顺序不影响既有 `prefix(5)` 的补充页插入逻辑。
