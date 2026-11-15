import ApplicationServices
import CoreGraphics
import Foundation

/// 鼠标模式的核心注入内核：用 `CGEvent` 发出指针移动、左右键与滚轮。
///
/// 与既有键盘注入（`KeyboardInjector`）并列，独立实现，不依赖作者其他模块；
/// 调用方负责在主线程或指定 RunLoop 触发（HID 事件已在这些线程上派发）。
struct MouseInjector {
    /// 单步移动指针（方向键单击或加速循环的每一步）。
    func move(_ button: RemoteButton, step: Int) {
        let (dx, dy) = MouseModeDefaults.displacement(for: button, step: step)
        moveBy(dx: dx, dy: dy)
    }

    /// 按合成向量移动指针（同时按住多个方向键时按帧合成一次，对角线不提速）。
    func moveBy(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        postMouseMove(dx: dx, dy: dy)
    }

    func clickLeft() { postClick(button: .left) }
    func clickRight() { postClick(button: .right) }

    /// `wheelUp = true` 向上滚，否则向下滚。`notches` 为滚动格数。
    func scroll(wheelUp: Bool, notches: Int = 1) {
        postScroll(delta: wheelUp ? notches : -notches)
    }

    // MARK: - CGEvent 封装

    private func postMouseMove(dx: Int, dy: Int) {
        let current = CGEvent(source: nil)?.location ?? CGPoint.zero
        let target = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) else { return }
        event.location = target
        event.post(tap: .cghidEventTap)
    }

    private func postClick(button: CGMouseButton) {
        let position = CGEvent(source: nil)?.location ?? CGPoint.zero
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: downType,
            mouseCursorPosition: position,
            mouseButton: button
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: upType,
            mouseCursorPosition: position,
            mouseButton: button
        ) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postScroll(delta: Int) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(delta),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
}
