import Foundation
import Testing

@testable import RemoteMic

struct CustomModeTests {

    @Test func defaultConfigurationHasNoModes() {
        #expect(CustomModeConfiguration().modes.isEmpty)
    }

    @Test func toggleTargetMatchesButtonAndTrigger() {
        let toggle = CustomModeToggle(button: .menu, trigger: .doubleClick)
        let mode = CustomMode(id: UUID(), name: "编辑", toggle: toggle)
        #expect(CustomModeController.toggleTarget(in: [mode], button: .menu, trigger: .doubleClick) == mode.id)
        // 触发方式必须精确匹配：单击不误触发双击切换。
        #expect(CustomModeController.toggleTarget(in: [mode], button: .menu, trigger: .singleClick) == nil)
        // 其他键不匹配。
        #expect(CustomModeController.toggleTarget(in: [mode], button: .ok, trigger: .doubleClick) == nil)
    }

    @Test func toggleTargetPicksFirstOnConflict() {
        let toggle = CustomModeToggle(button: .tv, trigger: .singleClick)
        let first = CustomMode(id: UUID(), name: "A", toggle: toggle)
        let second = CustomMode(id: UUID(), name: "B", toggle: toggle)
        #expect(CustomModeController.toggleTarget(in: [first, second], button: .tv, trigger: .singleClick) == first.id)
    }

    @Test func noToggleReturnsNil() {
        let mode = CustomMode(id: UUID(), name: "无切换键", toggle: nil)
        #expect(CustomModeController.toggleTarget(in: [mode], button: .tv, trigger: .singleClick) == nil)
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
            id: UUID(), name: "阅读", showsIndicator: true, indicatorColorHex: "FF453A",
            toggle: CustomModeToggle(button: .menu, trigger: .doubleClick)
        )
        mode.setAction(ConfiguredButtonAction(action: .pageDown, shortcut: nil),
                       for: .down, trigger: .singleClick)
        let config = CustomModeConfiguration(modes: [mode])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CustomModeConfiguration.self, from: data)
        #expect(decoded == config)
    }

    @Test func legacyJSONWithoutNewFieldsUsesDefaults() throws {
        // 模拟旧版本缺 toggle/showsIndicator/indicatorColorHex/bindings 的配置。
        let json = """
        {"modes":[{"id":"00000000-0000-0000-0000-000000000001","name":"旧模式"}]}
        """
        let decoded = try JSONDecoder().decode(
            CustomModeConfiguration.self, from: Data(json.utf8)
        )
        #expect(decoded.modes.count == 1)
        #expect(decoded.modes[0].showsIndicator == true)
        #expect(decoded.modes[0].indicatorColorHex == nil)
        #expect(decoded.modes[0].toggle == nil)
        #expect(decoded.modes[0].bindings.isEmpty)
    }

    @Test func indicatorColorParsesHexAndRejectsInvalid() {
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: nil).indicatorColor == nil)
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: "ZZZZZZ").indicatorColor == nil)
        #expect(CustomMode(id: UUID(), name: "M", indicatorColorHex: "0A84FF").indicatorColor != nil)
    }

    @Test func controllerToggleAndDeactivate() {
        let controller = CustomModeController()
        let a = CustomMode(id: UUID(), name: "A", toggle: CustomModeToggle(button: .menu, trigger: .doubleClick))
        let b = CustomMode(id: UUID(), name: "B", toggle: CustomModeToggle(button: .tv, trigger: .singleClick))
        controller.apply(configuration: CustomModeConfiguration(modes: [a, b]))

        // 未激活时无动作覆盖。
        #expect(controller.resolvedAction(for: .up, trigger: .singleClick) == nil)

        controller.activate(modeID: a.id)
        #expect(controller.activeModeID == a.id)
        let action = ConfiguredButtonAction(action: .arrowUp, shortcut: nil)
        var updatedA = a
        updatedA.setAction(action, for: .up, trigger: .singleClick)
        controller.apply(configuration: CustomModeConfiguration(modes: [updatedA, b]))
        #expect(controller.resolvedAction(for: .up, trigger: .singleClick) == action)

        // 再按同一切换键退出。
        controller.toggle(modeID: a.id)
        #expect(controller.activeModeID == nil)
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
            "custom_mode.toggle.title", "custom_mode.toggle.button", "custom_mode.toggle.trigger",
            "custom_mode.mapping.title", "custom_mode.action.title", "custom_mode.action.clear",
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
