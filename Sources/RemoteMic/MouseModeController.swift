import Combine
import Dispatch
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
    /// 连续移动定时器（GCD 源，确保跨线程可靠触发）。
    private var accelSource: DispatchSourceTimer?
    /// 松开防抖任务：合并遥控器的「按-放-按」自动重复为持续按住，避免连续移动被打断。
    private var releaseDebounce: [RemoteButton: DispatchWorkItem] = [:]

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
            // 退出立即隐藏光标反馈圈，不等它自己的 idle 超时（此前圈会滞留）。
            cursorFeedback.cancelInteraction(reason: "mouse_mode_off")
            AppLogger.shared.write("MOUSE MODE phase=state result=off")
            return
        }
        // 进入模式：立即显示指针圈（光标位置由注入器每步从系统真实坐标读取，
        // 无需在此播种，避免「跳回原处 / 飞到原点」）。
        cursorFeedback.handle(.pointerMoved(
            deltaX: 0, deltaY: 0,
            speed: Double(configuration.acceleration.baseStep)
        ))
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

    /// 返回 `.action`（应执行鼠标动作），`nil` 表示不接管（交由正常映射处理）。
    ///
    /// 进入 / 退出鼠标模式**只**由「按键映射」页绑定的「切换鼠标模式」动作触发
    /// （见 `HIDRemoteMonitor.performConfiguredAction` 的前置检查），本控制器不再保留
    /// 任何内置开关键，确保「按键映射」页是唯一权威来源。
    func resolve(_ button: RemoteButton, _ trigger: ButtonTrigger) -> Resolution? {
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
            // 取消该键可能挂起的「停止」任务：自动重复（按-放-按）被合并为持续按住。
            let wasIdle = pressing.isEmpty
            releaseDebounce[button]?.cancel()
            releaseDebounce.removeValue(forKey: button)
            pressing.insert(button)
            // 新一轮按下（此前无方向键按住）必须从当前时刻重新计时。
            // 若沿用异常残留的旧 holdStart，held 会很大，步长直接顶到 maxStep，
            // 表现为「刚进模式按一下就飞到屏幕边缘」。
            if wasIdle || holdStart == nil { holdStart = Date() }
            // 首次按下：只走一步，实现精确的离散控制。
            let step = configuration.acceleration.baseStep
            injector.move(button, step: step)
            cursorFeedback.handle(.pointerMoved(deltaX: 0, deltaY: 0, speed: Double(step)))
            beginAccelerationIfNeeded()
            return true
        case .release:
            // 暂移出「按住集合」，但若 80ms 内再次按下（自动重复）则忽略此次松开，
            // 连续定时器不被打断；真正松开（无后续按下）才停止全部移动。
            pressing.remove(button)
            guard pressing.isEmpty else { return true }
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.releaseDebounce.removeValue(forKey: button)
                guard self.pressing.isEmpty else { return }
                self.stopAllMovement()
            }
            releaseDebounce[button] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
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
        guard accelSource == nil else { return }
        let interval = Double(configuration.acceleration.stepInterval) / 1000.0
        // 关键：定时器回调必须在主线程执行，与 edge()/stopAllMovement()/release 防抖
        // 串行访问 pressing、holdStart、accelSource，消除跨线程竞态。
        // 竞态曾导致 tick 有时读到空 pressing（长按不持续），有时读到残留的旧 holdStart
        // 使步长直接顶到 maxStep（按一下就飞到屏幕边缘）。
        let src = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        src.schedule(deadline: .now() + interval, repeating: interval)
        src.setEventHandler { [weak self] in self?.accelTick() }
        src.resume()
        accelSource = src
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
        accelSource?.cancel()
        accelSource = nil
        releaseDebounce.values.forEach { $0.cancel() }
        releaseDebounce.removeAll()
        holdStart = nil
        pressing.removeAll()
    }
}
