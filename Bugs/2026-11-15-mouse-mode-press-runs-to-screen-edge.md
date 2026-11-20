# 鼠标模式方向键一按就冲到屏幕边缘、长按不连续

## 复现证据

- 用户实测：进入鼠标模式后按方向键一次，光标持续移动到屏幕边缘才停；上下左右同理；到边缘后各方向都“不好使”，只有用真实鼠标把光标移回屏幕中间后点按才能移动一点；长按没有连续移动效果。
- 日志缺口：`runtime.log` 里只有 `phase=toggle` / `phase=action` / `phase=state`，完全没有方向键 press/release 边沿日志，无法从日志判断释放是否到达——这正是问题长期未被定位的原因之一。
- 用户明确反馈该问题在最近多轮鼠标模式改动之前就存在，已按“非简单 Bug、证据驱动”流程调查。

## 调查过程与根因

1. 对照实验（临时脚本，不入仓）验证坐标链路：
   - `CGEvent` 绝对坐标注入会正确更新 `NSEvent.mouseLocation`（注入 (500,400) 后读到 (500, 主屏高-400)）。
   - 紧密循环下坐标回读不刷新（8 帧均读到同一旧值），但按真实 16–20ms 节奏注入时，“回读 + 绝对坐标”与“自维护坐标”都能正确逐帧累积。
   - 结论：坐标数学与定时器线程不是本次症状的根因，前几轮围绕“飞到原点/竞态/防抖”的修补方向不对。
2. 追踪边沿链路发现确定性缺陷：
   - 方向键 press 在 `RemoteButtonInteractionController.handle` 开头被 `mouseModeEdgeHandler` 消费并 `return`（`RemoteButtonInteraction.swift:54`），该分支**不创建 `Interaction`**。
   - `HIDRemoteMonitor` 的释放分支只在 `buttonInteractions.isTracking(button)` 为真时才转发 `.release`（`HIDRemoteMonitor.swift` 释放循环）。被鼠标模式消费的方向键从未 track，因此 `isTracking` 恒为 false，**释放事件永远到不了 `MouseModeController.edge(.release)`**。
   - 结果：`MouseModeController.pressing` 集合永不清空，`accelSource` 定时器永不停止；按下后按 `baseStep + acceleration × 时长` 持续注入位移直到 `maxStep`，光标一路冲到屏幕边缘。到达边缘后目标坐标越界被系统 clamp，表现为“方向键不好使”；真实鼠标把光标移回中间后，下一次按下从新的真实坐标走一步，才看似恢复。

## 修复

- `HIDRemoteMonitor` 释放分支在 `isTracking` 门控**之前**，先把 `.release` 交给同一个 `mouseModeEdgeHandler`；被消费则 `scheduleNonRepeatableRelease` 后 `continue`，不再落入手势状态机。
- `MouseModeController.edge` 补齐 press/release、首次步长、`pressing` 计数、加速定时器启停的脱敏日志；`stopAllMovement` 带停止原因。
- 新增回归测试：被 edge handler 消费的 press 不会创建 Interaction（`isTracking == false`），但 release 仍能被同一 handler 接受——锁定“释放必须绕过 isTracking 门控独立转发”这一契约。

## 验证

- `xcrun swift test --disable-keychain --filter "MouseModeTests|RemoteButtonInteractionTests|SettingsPageRegressionTests"`：132 tests 通过。
- 新增日志字段可直接观察 `phase=edge button=... edge=press/release pressing=N` 与 `phase=move_stopped reason=release_debounce`，用于确认释放到达且加速停止。
- 未覆盖：真实遥控器长按连续移动的最终手感与第三方 App 中的实际光标轨迹仍需真机验收；单元测试与离屏实验只证明边沿链路和坐标注入逻辑，不能替代真实设备与用户流程。
