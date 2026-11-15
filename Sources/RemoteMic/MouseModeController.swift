import Combine
import Foundation

/// 鼠标模式运行时控制器：持有开关、当前配置，解析按键，驱动线性加速移动。
///
/// 单例设计让 `HIDRemoteMonitor` / `RemoteButtonInteraction` 的薄 hook 默认咨询本实例，
/// 从而无需改动协调器构造点，diff 最小、便于作者整体采纳或丢弃。
/// `enabled = false` 时 `resolve` / `edge` 全部返回「不接管」，稳定行为零变化。
final class MouseModeController: ObservableObject {
    static let shared = MouseModeController()

    @Published private(set) var isActive: Bool = false
    private(set) var configuration: MouseModeConfiguration = MouseModeConfiguration()

    private let injector = MouseInjector()
    private let cursorFeedback = SiriRemoteCursorFeedbackController()

    /// 当前仍被按住的方向键（用于加速循环判断）。
    private var pressing = Set<RemoteButton>()
    /// 任一方向键首次按下的时刻（全部松开后清空，倍率随之复位）。
    private var holdStart: Date?
    private var accelTimer: Timer?

    /// 连续移动启动延迟：按下后先只走「首次那一步」，超过该时长才进入连续加速
    /// （与参考实现 `START_DELAY_MS = 180` 一致，保证单按精确走一步）。
    private let holdDelay: TimeInterval = 0.18

    // MARK: - 配置

    /// 由 `AppSettings` 在加载与每次修改后推送。
    /// 总开关关闭时强制退出鼠标模式；开启时不自动激活——
    /// 激活 / 退出由映射页绑定的「切换鼠标模式」动作（或 TV 键）用遥控器触发。
    func apply(configuration: MouseModeConfiguration) {
        self.configuration = configuration
        if !configuration.enabled { setActive(false) }
    }

    // MARK: - 开关

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if !active {
            stopAllMovement()
            AppLogger.shared.write("MOUSE MODE phase=state result=off")
            return
        }
        AppLogger.shared.write("MOUSE MODE phase=state result=on")
    }

    func toggle() {
        setActive(!isActive)
    }

    // MARK: - 触发解析（供 `HIDRemoteMonitor.performConfiguredAction` 薄 hook）

    enum Resolution: Equatable {
        case toggle
        case action(ConfiguredButtonAction)
    }

    /// 返回 `.toggle`（应切换模式）或 `.action`（应执行鼠标动作），`nil` 表示不接管。
    func resolve(_ button: RemoteButton, _ trigger: ButtonTrigger) -> Resolution? {
        // 配置的开关键（默认 TV 单击）仅在侧栏总开关开启时作为遥控器进出模式的
        // 备用入口；映射页绑定的「切换鼠标模式」动作则不受该开关限制。
        if configuration.enabled, button == configuration.toggle.button {
            let isToggleTrigger = trigger == configuration.toggle.trigger
            guard isActive else {
                return isToggleTrigger ? .toggle : nil
            }
            return isToggleTrigger ? .toggle : .action(ConfiguredButtonAction.disabled)
        }
        guard isActive else { return nil }
        guard let action = MouseModeDefaults.binding(
            for: button,
            volumeScrollInverted: configuration.volumeScrollInverted
        ) else {
            return nil // 其他键保持原有绑定
        }
        return .action(ConfiguredButtonAction(action: action, shortcut: nil))
    }

    // MARK: - 边缘处理（供 `RemoteButtonInteraction.handle` 薄 hook，仅方向键消费）

    /// 返回 `true` 表示事件已被鼠标模式消费（gesture 状态机不再处理该键）。
    ///
    /// 步进节奏与参考实现（`鼠标步进驱动/src/main.rs`）一致：
    /// 首次按下只走一步；按住超过 `holdDelay` 后由 16ms 一帧的连续循环驱动，
    /// 步长随按住时长线性放大，全部松开立即复位。
    func edge(_ button: RemoteButton, _ phase: RemoteButtonPhase) -> Bool {
        guard isActive, MouseModeDefaults.movedButtons.contains(button) else { return false }
        switch phase {
        case .press:
            pressing.insert(button)
            if holdStart == nil { holdStart = Date() }
            // 首次按下：只走一步，实现精确的离散控制。
            let step = configuration.acceleration.baseStep
            injector.move(button, step: step)
            cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: Double(step)))
            beginAccelerationIfNeeded()
            return true
        case .release:
            pressing.remove(button)
            if pressing.isEmpty {
                stopAllMovement()
            }
            return true
        }
    }

    /// 离散鼠标动作（左 / 右键、滚轮）的执行入口。
    func perform(_ configured: ConfiguredButtonAction) -> Bool {
        switch configured.action {
        case .mouseLeftClick:
            injector.clickLeft()
            cursorFeedback.handle(.clicked)
            return true
        case .mouseRightClick:
            injector.clickRight()
            cursorFeedback.handle(.clicked)
            return true
        case .mouseScrollUp:
            injector.scroll(wheelUp: true)
            return true
        case .mouseScrollDown:
            injector.scroll(wheelUp: false)
            return true
        default:
            return false
        }
    }

    // MARK: - 线性加速（按住时长驱动，与方向无关，X/Y 完全对称）

    /// 启动连续移动循环：16ms 一帧；每帧若已按住超过 `holdDelay`，
    /// 步长按 `步长 = 基础步长 + 加速度 × 连续时长` 线性放大（上限 `maxStep`）。
    /// 同帧内按住的多个方向合成一个向量，只发一次移动（对角线不提速）。
    private func beginAccelerationIfNeeded() {
        guard accelTimer == nil else { return }
        let interval = Double(configuration.acceleration.stepInterval) / 1000.0
        accelTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.accelTick()
        }
    }

    private func accelTick() {
        guard isActive, !pressing.isEmpty, let holdStart else { return }
        let held = Date().timeIntervalSince(holdStart)
        guard held >= holdDelay else { return } // 还没到连续阶段：仅保留首次那一步
        let continuous = held - holdDelay
        let accel = configuration.acceleration
        let step = min(
            accel.maxStep,
            Int(Double(accel.baseStep) + Double(accel.acceleration) * continuous)
        )
        let dx = (pressing.contains(.right) ? step : 0) - (pressing.contains(.left) ? step : 0)
        let dy = (pressing.contains(.down) ? step : 0) - (pressing.contains(.up) ? step : 0)
        injector.moveBy(dx: dx, dy: dy)
        cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: Double(step)))
    }

    private func stopAllMovement() {
        accelTimer?.invalidate()
        accelTimer = nil
        holdStart = nil
        pressing.removeAll()
    }
}
