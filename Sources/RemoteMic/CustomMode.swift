import AppKit
import Foundation

/// 用户可创建的输入模式。
///
/// 「普通模式」不在这里——它就是 AppSettings 的常规按键映射；本结构只存用户新建的模式。
/// 每个模式持有独立的一套绑定：表里没有的槽位回退到普通模式映射，
/// 因此新增模式不必复制全部按键，只需声明差异。
struct CustomMode: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// 进入模式时是否显示常驻指示圈（不同模式用不同颜色区分）。
    var showsIndicator: Bool
    /// 指示圈颜色（RRGGBB，不含 `#`）；`nil` 跟随系统强调色。
    var indicatorColorHex: String?
    /// 切换到本模式的按键 + 触发。未配置时该模式只能由其他模式的绑定进入。
    var toggle: CustomModeToggle?
    /// 该模式独立的一套绑定。
    var bindings: [CustomModeBinding]

    init(
        id: UUID = UUID(),
        name: String,
        showsIndicator: Bool = true,
        indicatorColorHex: String? = nil,
        toggle: CustomModeToggle? = nil,
        bindings: [CustomModeBinding] = []
    ) {
        self.id = id
        self.name = name
        self.showsIndicator = showsIndicator
        self.indicatorColorHex = indicatorColorHex
        self.toggle = toggle
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, showsIndicator, indicatorColorHex, toggle, bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // 旧配置缺这些字段时给合理默认值，保证 schema 演进可读。
        showsIndicator = try container.decodeIfPresent(Bool.self, forKey: .showsIndicator) ?? true
        indicatorColorHex = try container.decodeIfPresent(String.self, forKey: .indicatorColorHex)
        toggle = try container.decodeIfPresent(CustomModeToggle.self, forKey: .toggle)
        bindings = try container.decodeIfPresent([CustomModeBinding].self, forKey: .bindings) ?? []
    }

    func action(for button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction? {
        bindings.first { $0.button == button.rawValue && $0.trigger == trigger.rawValue }?.configured
    }

    mutating func setAction(
        _ action: ConfiguredButtonAction?,
        for button: RemoteButton,
        trigger: ButtonTrigger
    ) {
        bindings.removeAll { $0.button == button.rawValue && $0.trigger == trigger.rawValue }
        if let action {
            bindings.append(CustomModeBinding(
                button: button.rawValue,
                trigger: trigger.rawValue,
                configured: action
            ))
        }
    }

    var indicatorColor: NSColor? {
        MouseModeConfiguration.cursorRingColor(from: indicatorColorHex)
    }
}

/// 切换到某模式的按键 + 触发方式。
struct CustomModeToggle: Codable, Equatable {
    var button: RemoteButton
    var trigger: ButtonTrigger
}

/// 模式内的一个槽位绑定。用字符串存键与触发，便于 Codable 与导出校验。
struct CustomModeBinding: Codable, Equatable {
    var button: String
    var trigger: String
    var configured: ConfiguredButtonAction
}

/// 所有用户模式的持久化容器。
struct CustomModeConfiguration: Codable, Equatable {
    var modes: [CustomMode] = []
}
