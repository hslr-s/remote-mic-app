# 自定义模式（Custom Modes）产品规范

## 目标

把「普通模式 / 鼠标模式」扩展为可创建的任意多模式：每个自定义模式持有独立的一套按键映射、
一个进入/退出用的切换按键，以及可选的彩色模式指示圈（不同颜色区分不同模式）。
预设的鼠标模式行为完全不变。

## 范围与非目标

- 自定义模式是**纯按键映射切换**：不提供鼠标模式的指针移动/加速/滚动，
  不接管方向键边沿，不共享鼠标控制器状态。
- 鼠标模式保持现状：仍由「按键映射」页的「切换鼠标模式」动作控制，与自定义模式互斥
  （进入任一侧都会先退出另一侧）。
- 不做配置导出/导入（自定义模式使用独立 UserDefaults 键 `customModeConfiguration`）。

## 数据模型

- `CustomMode`：`id`、`name`、`showsIndicator`、`indicatorColorHex`（nil=跟随系统强调色）、
  `toggle`（切换键+触发，可空）、`bindings`（稀疏绑定表）。
- `CustomModeConfiguration`：模式数组，整体 JSON 编解码，旧字段缺失时取默认值。
- 「普通模式」即「按键」页的常规映射，不在本模型中。

## 解析与运行时

1. **切换键**：`CustomModeController.toggleTarget(in:button:trigger:)` 纯匹配，
   在 `HIDRemoteMonitor.performConfiguredAction` 的 `overrideActionPerformer` 之后、
   普通映射解析之前拦截。优先级高于映射页绑定与模式内绑定；多个模式占用同一槽位取第一个
   （UI 有冲突提示）。
2. **进入/退出**：按切换键进入目标模式；再按同一切换键退出回普通模式。
   按其他模式的切换键直接切过去。
3. **模式内映射**：激活模式下，槽位在绑定表中的条目覆盖普通映射；
   未设置的槽位走原普通映射（`customModeActionResolver` 返回 nil 时不拦截）。
4. **互斥**：进入自定义模式前 `MouseModeController.setActive(false)`；
   `.mouseModeToggle` 分支进入鼠标模式前 `CustomModeController.deactivate`。
5. **指示圈**：`showsIndicator` 开启时进入模式即在光标位置显示常驻彩色圈
   （复用 `SiriRemoteCursorFeedbackController` 的 pin + ringColor 机制）；
   退出或关闭指示圈时解除 pin。鼠标模式的反馈圈实例独立，不受影响。
6. **激活模式被删除**时立即退出（`apply(configuration:)` 保证）。
7. **日志**：`CUSTOM MODE phase=toggle/state/action` 脱敏日志，不含坐标与窗口标题。

## 设置页（侧栏「自定义模式」）

1. 模式列表：横向 chip，含指示色圆点；输入名称「新建模式」。
2. 模式详情：
   - 模式名称 + 删除按钮。
   - 模式指示圈：显示开关、6 色预设色板、自定义 ColorPicker、跟随系统按钮。
   - 切换按键：按键 Picker + 触发 Picker；与其他模式冲突时橙色提示。
   - 模式内按键映射：复用遥控器画布；槽位摘要显示本模式动作或
     「普通：<普通映射动作>」；点击槽位弹出动作选择 Sheet
     （不含需要额外载荷的动作：自定义快捷键/组合/指定 App/常用语/长录音）。
     Sheet 内可清除该槽位（恢复普通映射）。
3. 侧栏顺序：`customModes` 位于 `privateFeature` 之后、`about` 之前，
   不影响既有 `prefix(5)` 的补充页插入逻辑。

## 默认与兼容

- 默认无自定义模式；所有行为与此前一致（未激活完全 passthrough）。
- 旧配置无 `customModeConfiguration` 键 → 空列表；JSON 缺字段 → 默认值。
- 切换键槽位与映射页绑定重叠时，切换优先；这是有意的"切换键专用"语义。
