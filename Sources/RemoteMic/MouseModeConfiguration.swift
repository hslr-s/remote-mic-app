import Foundation

/// 鼠标模式的持久化配置。
///
/// 结构独立、可版本化，存放在 `AppSettings` 自己的 key 下，不复用作者既有的
/// `RemoteButtonInteractionSettings.modes` 字段（那个字段作者用来存「按住模式」）。
/// 配置只描述「开关、启用键、滚轮互换、加速参数」，方向 / 确认 / 菜单的鼠标映射是写死的
/// （见 `MouseModeDefaults`），v2 若要放开编辑只加一个可选的覆盖字典即可。
struct MouseModeConfiguration: Codable, Equatable {
    /// 全局开关，默认关闭：关闭时整条运行时链路 passthrough，稳定行为零变化。
    var enabled: Bool = false

    /// 启用 / 退出鼠标模式的「按键 + 触发方式」。
    var toggle: MouseModeToggle = MouseModeToggle()

    /// 音量 + / 音量 - 映射到滚轮上 / 下的方向互换（仅这两个键可换，方向键不换）。
    var volumeScrollInverted: Bool = false

    /// 线性加速参数（像素 / 毫秒）。
    var acceleration: MouseAcceleration = MouseAcceleration()

    struct MouseModeToggle: Codable, Equatable {
        /// 默认用 `.tv`：它不在鼠标模式固定映射集合内，避免与方向 / 确认 / 菜单冲突。
        var button: RemoteButton = .tv
        var trigger: ButtonTrigger = .singleClick
    }

    struct MouseAcceleration: Codable, Equatable {
        /// 单击或按住初段每步移动的像素（参考实现 `STEP = 10`）。
        var baseStep: Int = 10
        /// 每连续按住 1 秒增加的像素（线性加速斜率；参考实现等效 2 × baseStep）。
        var acceleration: Int = 20
        /// 单步位移上限，避免无限加速（参考实现等效 8 × baseStep）。
        var maxStep: Int = 80
        /// 连续移动循环间隔（毫秒，参考实现 `MOVE_TICK_MS = 16`）。
        var stepInterval: Int = 16

        var isValid: Bool {
            baseStep > 0 && acceleration >= 0 && maxStep >= baseStep &&
                (1...100).contains(stepInterval)
        }
    }
}

/// 鼠标模式固定映射（v1 写死，编辑器置灰只读）。
///
/// 只有这些键在鼠标模式激活时被接管；其余键保持原有（非鼠标模式）绑定。
/// 语音键与开关键由运行时单独排除，不在此表内。
enum MouseModeDefaults {
    /// 方向键：进入模式后由「按下 = 步进、按住 = 加速」驱动，不进单击 / 双击 / 长按手势。
    static let movedButtons: Set<RemoteButton> = [.up, .down, .left, .right]

    /// 鼠标模式固定接管的全部按键。
    static let mouseButtons: Set<RemoteButton> = [
        .up, .down, .left, .right, .ok, .menu, .volumeUp, .volumeDown,
    ]

    /// 返回某键在鼠标模式下的固定动作；不在集合内返回 `nil`（passthrough）。
    ///
    /// 保留无 trigger 版本供「整键占用」展示（方向 / OK / 音量三个槽位都占用）。
    /// 实际运行时请用 `binding(for:trigger:volumeScrollInverted:)`，它按槽位精确判定：
    /// 菜单键只占用单击这一个槽位，双击 / 长按仍走映射页自定义。
    static func binding(
        for button: RemoteButton,
        volumeScrollInverted: Bool
    ) -> ButtonAction? {
        binding(for: button, trigger: .singleClick, volumeScrollInverted: volumeScrollInverted)
    }

    /// 按「键 + 触发方式」精确判定鼠标模式占用。
    ///
    /// - 方向键：单击/双击/长按都由「按下=步进、按住=加速」的边沿逻辑接管，不进手势；
    ///   三个槽位都算占用，展示固定「移动」说明。
    /// - OK：整键占用为鼠标左键。
    /// - 菜单：**只占用单击** = 鼠标右键；双击 / 长按 passthrough 到映射页（可自定义）。
    /// - 音量 ±：整键占用为滚轮上 / 下（可互换）。
    /// - 其他键：`nil`，passthrough。
    static func binding(
        for button: RemoteButton,
        trigger: ButtonTrigger,
        volumeScrollInverted: Bool
    ) -> ButtonAction? {
        switch button {
        case .up: return .mouseMoveUp
        case .down: return .mouseMoveDown
        case .left: return .mouseMoveLeft
        case .right: return .mouseMoveRight
        case .ok:
            return .mouseLeftClick
        case .menu:
            // 只占用单击这一个槽位。
            return trigger == .singleClick ? .mouseRightClick : nil
        case .volumeUp:
            return volumeScrollInverted ? .mouseScrollDown : .mouseScrollUp
        case .volumeDown:
            return volumeScrollInverted ? .mouseScrollUp : .mouseScrollDown
        default:
            return nil
        }
    }

    /// 某键某槽位在鼠标模式下是否被固定占用。
    static func isReserved(
        button: RemoteButton,
        trigger: ButtonTrigger,
        volumeScrollInverted: Bool
    ) -> Bool {
        binding(for: button, trigger: trigger, volumeScrollInverted: volumeScrollInverted) != nil
    }

    /// 方向键对应的屏幕位移。
    /// CGEvent 全局坐标原点在左上角、y 轴向下为正（与参考实现一致）：
    /// 上 = -y、下 = +y、左 = -x、右 = +x。
    static func displacement(for button: RemoteButton, step: Int) -> (dx: Int, dy: Int) {
        switch button {
        case .up: return (0, -step)
        case .down: return (0, step)
        case .left: return (-step, 0)
        case .right: return (step, 0)
        default: return (0, 0)
        }
    }
}
