import ApplicationServices
import CoreGraphics
import Foundation

/// 鼠标模式的核心注入内核：用 `CGEvent` 发出指针移动、左右键与滚轮。
///
/// 与既有键盘注入（`KeyboardInjector`）并列，独立实现，不依赖作者其他模块。
/// 设计为引用类型，内部维护 `lastPos` 以避免每一步都重新读取系统光标坐标
/// （首次读取可能返回 0 或 nil，导致光标瞬间跳到原点「飞走」）。
final class MouseInjector {
    /// 最近一次发出的指针位置；每次移动后更新，使连续移动与系统光标保持同步，
    /// 同时避免回读失败时的原点跳跃。
    private var lastPos: CGPoint?

    /// 单步移动指针（方向键单击或加速循环的每一步）。
    func move(_ button: RemoteButton, step: Int) {
        let (dx, dy) = MouseModeDefaults.displacement(for: button, step: step)
        moveBy(dx: dx, dy: dy)
    }

    /// 按合成向量移动指针（同时按住多个方向键时按帧合成一次，对角线不提速）。
    ///
    /// 优先读取系统真实光标位置（与触控板移动保持同步）；读取失败（无事件源）时
    /// 回退到 `lastPos`；两者都拿不到则**跳过本次移动**，绝不跳到原点。
    func moveBy(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        let read = CGEvent(source: nil)?.location
        guard let current = read ?? lastPos else { return }
        let target = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        lastPos = target
        postMouseMove(to: target)
    }

    func clickLeft() { postClick(button: .left) }
    func clickRight() { postClick(button: .right) }

    /// `wheelUp = true` 向上滚，否则向下滚。`notches` 为滚动格数。
    func scroll(wheelUp: Bool, notches: Int = 1) {
        postScroll(delta: wheelUp ? notches : -notches)
    }

    /// 鼠标模式退出时调用，下次进入重新从系统读取光标位置。
    func resetCursorTracking() { lastPos = nil }

    // MARK: - CGEvent 封装

    private func postMouseMove(to target: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postClick(button: CGMouseButton) {
        let position = CGEvent(source: nil)?.location ?? (lastPos ?? .zero)
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
