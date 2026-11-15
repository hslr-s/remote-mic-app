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
    private var accelTimers: [RemoteButton: Timer] = [:]
    private var accelSteps: [RemoteButton: Int] = [:]

    // MARK: - 配置

    /// 由 `AppSettings` 在加载与每次修改后推送。
    /// 勾选总开关即视为「进入鼠标模式」：自动激活，使方向键立即接管指针；
    /// 取消勾选则退出模式。TV 键的切换仍可用作运行期快速开关。
    func apply(configuration: MouseModeConfiguration) {
        self.configuration = configuration
        setActive(configuration.enabled)
    }

    // MARK: - 开关

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        if !active {
            isActive = false
            stopAllMovement()
            AppLogger.shared.write("MOUSE MODE phase=state result=off")
            return
        }
        // 功能关闭时不能进入鼠标模式：开关键只在 enabled 时有效。
        guard configuration.enabled else { return }
        isActive = true
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
        // 功能关闭时完全不接管：所有键（含开关键）保持原有绑定，零行为变化。
        guard configuration.enabled else { return nil }
        // 开关键：鼠标模式激活时只做切换；非激活时仅其配置的触发方式切换，其余触发 passthrough。
        if button == configuration.toggle.button {
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
    func edge(_ button: RemoteButton, _ phase: RemoteButtonPhase) -> Bool {
        guard isActive, MouseModeDefaults.movedButtons.contains(button) else { return false }
        switch phase {
        case .press:
            pressing.insert(button)
            let step = configuration.acceleration.baseStep
            injector.move(button, step: step)
            cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: Double(step)))
            beginAcceleration(for: button)
            return true
        case .release:
            pressing.remove(button)
            stopAcceleration(for: button)
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

    // MARK: - 线性加速

    private func beginAcceleration(for button: RemoteButton) {
        stopAcceleration(for: button)
        accelSteps[button] = configuration.acceleration.baseStep
        let holdDelay = 0.25
        accelTimers[button] = Timer.scheduledTimer(withTimeInterval: holdDelay, repeats: false) {
            [weak self] _ in
            guard let self, self.pressing.contains(button) else { return }
            self.scheduleAccelLoop(for: button)
        }
    }

    private func scheduleAccelLoop(for button: RemoteButton) {
        let interval = Double(configuration.acceleration.stepInterval) / 1000.0
        accelTimers[button] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] timer in
            guard let self, self.pressing.contains(button) else {
                timer.invalidate()
                return
            }
            var step = self.accelSteps[button] ?? self.configuration.acceleration.baseStep
            step = min(self.configuration.acceleration.maxStep, step + self.configuration.acceleration.acceleration)
            self.accelSteps[button] = step
            self.injector.move(button, step: step)
            self.cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: Double(step)))
        }
    }

    private func stopAcceleration(for button: RemoteButton) {
        accelTimers[button]?.invalidate()
        accelTimers[button] = nil
        accelSteps[button] = nil
    }

    private func stopAllMovement() {
        for button in pressing {
            stopAcceleration(for: button)
        }
        pressing.removeAll()
    }
}
