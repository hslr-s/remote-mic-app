import Combine
import Foundation

/// 自定义输入模式运行时控制器。
///
/// 与 `MouseModeController` 平行且互斥：任意时刻至多一个自定义模式激活，
/// 自定义模式激活时鼠标模式必须退出，反之亦然（由 `HIDRemoteMonitor` 的切换分支保证）。
/// 未激活时本控制器完全 passthrough，普通映射行为零变化。
final class CustomModeController: ObservableObject {
    static let shared = CustomModeController()

    @Published private(set) var activeModeID: UUID?
    private(set) var configuration = CustomModeConfiguration()

    private let cursorFeedback = SiriRemoteCursorFeedbackController()

    var activeMode: CustomMode? {
        guard let activeModeID else { return nil }
        return configuration.modes.first { $0.id == activeModeID }
    }

    /// 纯判定：给定按键 + 触发，返回应切换到的模式 ID。
    /// 多个模式配了同一槽位时取第一个，避免歧义（UI 会提示冲突）。
    static func toggleTarget(
        in modes: [CustomMode],
        button: RemoteButton,
        trigger: ButtonTrigger
    ) -> UUID? {
        for mode in modes {
            guard let toggle = mode.toggle,
                  toggle.button == button, toggle.trigger == trigger else { continue }
            return mode.id
        }
        return nil
    }

    /// 由 `AppSettings` 在加载与每次修改后推送。
    func apply(configuration: CustomModeConfiguration) {
        self.configuration = configuration
        // 激活模式被删除：立即退出，避免停留在不存在的模式。
        if let activeModeID, !configuration.modes.contains(where: { $0.id == activeModeID }) {
            deactivate(reason: "mode_deleted")
        } else if activeModeID != nil {
            refreshIndicator()
        }
    }

    /// 按切换键：目标是当前模式则退出，否则切到目标模式。
    func toggle(modeID: UUID) {
        if activeModeID == modeID {
            deactivate(reason: "toggle_off")
        } else {
            activate(modeID: modeID)
        }
    }

    func activate(modeID: UUID) {
        guard let mode = configuration.modes.first(where: { $0.id == modeID }) else { return }
        guard activeModeID != modeID else { return }
        activeModeID = modeID
        refreshIndicator()
        AppLogger.shared.write(
            "CUSTOM MODE phase=state result=on mode_id=\(modeID.uuidString) name=\(mode.name)"
        )
    }

    func deactivate(reason: String) {
        guard activeModeID != nil else { return }
        activeModeID = nil
        cursorFeedback.setModeIndicatorPinned(false, reason: "custom_mode_\(reason)")
        AppLogger.shared.write("CUSTOM MODE phase=state result=off reason=\(reason)")
    }

    /// 给定按键 + 触发是否有模式把它设为切换键。
    func toggleModeID(for button: RemoteButton, trigger: ButtonTrigger) -> UUID? {
        Self.toggleTarget(in: configuration.modes, button: button, trigger: trigger)
    }

    /// 当前模式的槽位绑定；未设置返回 nil，由调用方回退到普通映射。
    func resolvedAction(for button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        guard let activeMode else { return nil }
        return activeMode.action(for: button, trigger: trigger)
    }

    private func refreshIndicator() {
        guard let mode = activeMode else {
            cursorFeedback.setModeIndicatorPinned(false, reason: "custom_mode_none")
            return
        }
        guard mode.showsIndicator else {
            cursorFeedback.setModeIndicatorPinned(false, reason: "custom_mode_indicator_off")
            return
        }
        cursorFeedback.setRingColor(mode.indicatorColor)
        cursorFeedback.setModeIndicatorPinned(true, reason: "custom_mode_on")
        // 在光标当前位置立即显示常驻圈，作为「已进入某模式」的视觉感知。
        cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: 0))
    }
}
