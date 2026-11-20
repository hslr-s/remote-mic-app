import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 鼠标模式的核心注入内核：用 `CGEvent` 发出指针移动、左右键与滚轮。
///
/// 与既有键盘注入（`KeyboardInjector`）并列，独立实现。
///
/// 设计要点：**每一步都读取系统真实光标位置**（`NSEvent.mouseLocation`，AppKit 可靠），
/// 在其基础上叠加位移后发出，**绝不缓存上一次坐标**。这样：
/// - 不会因「读不到坐标」而飞到屏幕原点（早期 `CGEvent(source:nil)?.location` 会返回 0,0）；
/// - 用户用真实鼠标/触控板移动光标后，下一次按方向键从真实位置继续，不会「跳回原处」；
/// - 连续加速驱动的每一帧也基于真实位置，移动自然衔接。
final class MouseInjector {
    /// 单步移动指针（方向键单击或加速循环的每一步）。
    func move(_ button: RemoteButton, step: Int) {
        let (dx, dy) = MouseModeDefaults.displacement(for: button, step: step)
        moveBy(dx: dx, dy: dy)
    }

    /// 按合成向量移动指针（同时按住多个方向键时按帧合成一次，对角线不提速）。
    func moveBy(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        postMouseMove(to: currentCursor(offsetBy: dx, dy: dy))
    }

    func clickLeft() { postClick(button: .left) }
    func clickRight() { postClick(button: .right) }

    /// `wheelUp = true` 向上滚，否则向下滚。`notches` 为滚动格数。
    func scroll(wheelUp: Bool, notches: Int = 1) {
        postScroll(delta: wheelUp ? notches : -notches)
    }

    // MARK: - 坐标

    /// 计算「当前真实光标位置 + 位移」后的目标点。
    ///
    /// `NSEvent.mouseLocation` 返回 Cocoa 全局坐标（原点主屏左下、y 向上），
    /// 而 `CGEvent` 全局坐标原点在主屏左上、y 向下；两者是同一全局坐标空间，
    /// 仅绕主屏原点翻转，故统一用 `主屏高度 - cocoaY` 转换，多屏也成立。
    private func currentCursor(offsetBy dx: Int, dy: Int) -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let current = CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)
        return CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
    }

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
        let position = currentCursor(offsetBy: 0, dy: 0)
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
