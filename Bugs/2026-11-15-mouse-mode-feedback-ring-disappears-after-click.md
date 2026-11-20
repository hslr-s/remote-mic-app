# 鼠标模式按左键后蓝色反馈圈消失

## 复现证据

- 用户实测：进入鼠标模式后蓝色反馈圈正常显示；按一次确定键（映射为鼠标左键）后圈立刻消失，必须再移动光标才重新出现。
- 用户影响：反馈圈同时承担“当前是否处于鼠标模式”的可视指示；消失后无法判断模式状态。

## 调查过程与根因

1. 反馈控制器 `SiriRemoteCursorFeedbackController.handle` 有三条自动隐藏路径：
   - `.clicked`：`scheduleHide(after: 0.12)`；
   - `.scrolled`：`scheduleHide(after: 0.55)`；
   - `.pointerMoved`：`schedulePointerIdleEvaluation(after: 0.24)`，无 AX 可点击目标时 `hide(reason: "pointer_idle_no_clickable_target")`。
2. 鼠标模式 `perform` 执行左/右键时调用 `cursorFeedback.handle(.clicked)`；方向键移动调用 `.pointerMoved`；滚轮也经同一控制器。
3. 根因：鼠标模式复用了触摸板的**瞬时反馈**语义，点击 0.12s 后自动隐藏；但鼠标模式下这个圈被用户当作**常驻模式指示器**，语义冲突。实例隔离已确认：`BridgeAppModel` 与 `MouseModeController` 各持一个 `SiriRemoteCursorFeedbackController`，可只改鼠标模式实例，不影响触摸板。

## 修复

- `SiriRemoteCursorFeedbackState.shouldAutoHide(isModeIndicatorPinned:)` 抽出隐藏决策（纯函数，可单测）。
- 控制器新增 `isModeIndicatorPinned` 与 `setModeIndicatorPinned(_:reason:)`：锁定时两个自动隐藏调度点直接返回，并取消残留隐藏任务；解锁时走原有 `cancelInteraction` 清理 AX 悬停状态并隐藏，新增 `phase=mode_indicator result=pinned` 日志。
- `MouseModeController.setActive(true)` 先锁定再显示；`setActive(false)` 解锁并隐藏。
- 触摸板实例默认未锁定，行为完全不变。

## 验证

- `xcrun swift test --disable-keychain --filter "SiriRemoteCursorFeedbackTests|MouseModeTests"`：31 tests 通过。
- 新增测试断言锁定/未锁定两种决策；日志 `phase=mode_indicator result=pinned` 可确认锁定生效。
- 未覆盖：真实遥控器点击/移动/滚轮下的常驻显示与退出即隐藏仍需真机验收；单元测试与构建不能替代用户流程。
