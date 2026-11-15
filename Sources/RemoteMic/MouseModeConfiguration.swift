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
        /// 单击或按住初段每步移动的像素。
        var baseStep: Int = 8
        /// 每 100ms 增加的像素（线性加速斜率）。
        var acceleration: Int = 4
        /// 单步位移上限，避免无限加速。
        var maxStep: Int = 60
        /// 加速循环间隔（毫秒）。
        var stepInterval: Int = 60

        var isValid: Bool {
            baseStep > 0 && acceleration >= 0 && maxStep >= baseStep &&
                (1...500).contains(stepInterval) && stepInterval % 10 == 0
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
    static func binding(
        for button: RemoteButton,
        volumeScrollInverted: Bool
    ) -> ButtonAction? {
        switch button {
        case .up: return .mouseMoveUp
        case .down: return .mouseMoveDown
        case .left: return .mouseMoveLeft
        case .right: return .mouseMoveRight
        case .ok: return .mouseLeftClick
        case .menu: return .mouseRightClick
        case .volumeUp: return volumeScrollInverted ? .mouseScrollDown : .mouseScrollUp
        case .volumeDown: return volumeScrollInverted ? .mouseScrollUp : .mouseScrollDown
        default: return nil
        }
    }

    /// 方向键对应的屏幕位移（dy 向上为正，macOS 坐标原点在左下）。
    static func displacement(for button: RemoteButton, step: Int) -> (dx: Int, dy: Int) {
        switch button {
        case .up: return (0, step)
        case .down: return (0, -step)
        case .left: return (-step, 0)
        case .right: return (step, 0)
        default: return (0, 0)
        }
    }
}
