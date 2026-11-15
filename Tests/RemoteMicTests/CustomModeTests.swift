import Foundation
import Testing

@testable import RemoteMic

struct CustomModeTests {

    @Test func defaultConfigurationHasNoModes() {
        #expect(CustomModeConfiguration().modes.isEmpty)
    }

    @Test func switchModeActionCarriesTargetModeID() {
        let modeID = UUID()
        let configured = ConfiguredButtonAction(
            action: .customModeToggle, shortcut: nil, modeID: modeID
        )
        #expect(configured.action == .customModeToggle)
        #expect(configured.modeID == modeID)
        // 普通动作不带 modeID。
        let plain = ConfiguredButtonAction(action: .arrowUp, shortcut: nil)
        #expect(plain.modeID == nil)
    }

    @Test func configuredActionWithoutModeIDDecodesFromLegacyJSON() throws {
        // 旧配置没有 modeID 字段：解码应给 nil，不影响原有动作。
        let json = """
        {"action":"arrowUp","shortcut":null,"applicationProfileID":null,"macroID":null}
        """
        let decoded = try JSONDecoder().decode(ConfiguredButtonAction.self, from: Data(json.utf8))
        #expect(decoded.action == .arrowUp)
        #expect(decoded.modeID == nil)
    }

    @Test func switchModeActionRoundTripsThroughJSON() throws {
        let modeID = UUID()
        let configured = ConfiguredButtonAction(
            action: .customModeToggle, shortcut: nil, modeID: modeID
        )
        let data = try JSONEncoder().encode(configured)
        let decoded = try JSONDecoder().decode(ConfiguredButtonAction.self, from: data)
        #expect(decoded == configured)
        #expect(decoded.modeID == modeID)
    }

    @Test func slotBindingsSetAndClear() {
        var mode = CustomMode(id: UUID(), name: "M")
        let action = ConfiguredButtonAction(action: .arrowUp, shortcut: nil)
        mode.setAction(action, for: .up, trigger: .singleClick)
        #expect(mode.action(for: .up, trigger: .singleClick) == action)
        // 同槽位重设覆盖，不重复累积。
        let replacement = ConfiguredButtonAction(action: .scrollUp, shortcut: nil)
        mode.setAction(replacement, for: .up, trigger: .singleClick)
        #expect(mode.bindings.count == 1)
        #expect(mode.action(for: .up, trigger: .singleClick) == replacement)
        // 不同触发互不干扰。
        mode.setAction(action, for: .up, trigger: .doubleClick)
        #expect(mode.bindings.count == 2)
        // 清除移除该槽位。
        mode.setAction(nil, for: .up, trigger: .singleClick)
        #expect(mode.action(for: .up, trigger: .singleClick) == nil)
        #expect(mode.action(for: .up, trigger: .doubleClick) == action)
    }

    @Test func configurationRoundTripsThroughJSON() throws {
        var mode = CustomMode(
            id: UUID(), name: "阅读", showsIndicator: true, indicatorColorHex: "FF453A"
        )
        mode.setAction(ConfiguredButtonAction(action: .pageDown, shortcut: nil),
                       for: .down, trigger: .singleClick)
        let config = CustomModeConfiguration(modes: [mode])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CustomModeConfiguration.self, from: data)
        #expect(decoded == config)
    }

    @Test func legacyJSONWithoutNewFieldsUsesDefaults() throws {
        // 模拟旧版本缺 showsIndicator/indicatorColorHex/bindings 的配置。
        let json = """
        {"modes":[{"id":"00000000-0000-0000-0000-000000000001","name":"旧模式"}]}
        """
        let decoded = try JSONDecoder().decode(
            CustomModeConfiguration.self, from: Data(json.utf8)
        )
        #expect(decoded.modes.count == 1)
        #expect(decoded.modes[0].showsIndicator == true)
        #expect(decoded.modes[0].indicatorColorHex == nil)
        #expect(decoded.modes[0].bindings.isEmpty)
    }

    @Test func indicatorColorParsesHexAndRejectsInvalid() {
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: nil).indicatorColor == nil)
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: "ZZZZZZ").indicatorColor == nil)
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: "0A84FF").indicatorColor != nil)
    }

    @Test func controllerToggleAndDeactivate() {
        let controller = CustomModeController()
        let a = CustomMode(id: UUID(), name: "A")
        let b = CustomMode(id: UUID(), name: "B")
        controller.apply(configuration: CustomModeConfiguration(modes: [a, b]))

        // 未激活时无动作覆盖。
        #expect(controller.resolvedAction(for: .up, trigger: .singleClick) == nil)

        // 按「切换模式」动作（携带 A 的 modeID）进入 A。
        controller.toggle(modeID: a.id)
        #expect(controller.activeModeID == a.id)
        let action = ConfiguredButtonAction(action: .arrowUp, shortcut: nil)
        var updatedA = a
        updatedA.setAction(action, for: .up, trigger: .singleClick)
        controller.apply(configuration: CustomModeConfiguration(modes: [updatedA, b]))
        #expect(controller.resolvedAction(for: .up, trigger: .singleClick) == action)

        // 再按同一切换键退出。
        controller.toggle(modeID: a.id)
        #expect(controller.activeModeID == nil)

        // 从 A 直接切到 B：切到别的 modeID 覆盖当前，而非退出。
        controller.activate(modeID: a.id)
        controller.toggle(modeID: b.id)
        #expect(controller.activeModeID == b.id)
    }

    @Test func controllerDeactivatesWhenActiveModeDeleted() {
        let controller = CustomModeController()
        let a = CustomMode(id: UUID(), name: "A")
        controller.apply(configuration: CustomModeConfiguration(modes: [a]))
        controller.activate(modeID: a.id)
        #expect(controller.activeModeID == a.id)
        controller.apply(configuration: CustomModeConfiguration(modes: []))
        #expect(controller.activeModeID == nil)
    }

    @Test func switchModeActionIsNotAppInternal() {
        // 切换模式由 HIDRemoteMonitor 按 action 分发，不应被当成 App 内部动作走通用内部通道。
        #expect(ButtonAction.customModeToggle.isAppInternal == false)
    }

    @Test func customModeLocalizedCopyIsComplete() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keys = [
            "settings.section.custom_modes",
            "custom_mode.page.title", "custom_mode.page.subtitle",
            "custom_mode.list.title", "custom_mode.new.placeholder", "custom_mode.new.button",
            "custom_mode.indicator.title", "custom_mode.indicator.enable", "custom_mode.indicator.custom",
            "custom_mode.indicator.follow_system",
            "custom_mode.mapping.title", "custom_mode.action.title", "custom_mode.action.clear",
            "action.custom_mode_toggle",
            "custom_mode.target.title", "custom_mode.target.empty", "custom_mode.target.create",
            "custom_mode.target.deleted", "custom_mode.target.deleted_short",
            "custom_mode.action.summary_prefix",
        ]
        for localization in ["zh-Hans", "en"] {
            let contents = try String(
                contentsOf: root.appendingPathComponent(
                    "Resources/\(localization).lproj/Localizable.strings"
                ),
                encoding: .utf8
            )
            for key in keys {
                #expect(contents.contains("\"\(key)\" ="), "missing \(key) in \(localization)")
            }
        }
    }
}
