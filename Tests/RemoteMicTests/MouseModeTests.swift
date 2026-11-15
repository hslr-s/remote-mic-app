import Foundation
import Testing
@testable import RemoteMic

struct MouseModeTests {
    // MARK: - 固定映射

    @Test func fixedBindingMapsDirectionAndButtons() {
        #expect(MouseModeDefaults.binding(for: .up, volumeScrollInverted: false) == .mouseMoveUp)
        #expect(MouseModeDefaults.binding(for: .down, volumeScrollInverted: false) == .mouseMoveDown)
        #expect(MouseModeDefaults.binding(for: .left, volumeScrollInverted: false) == .mouseMoveLeft)
        #expect(MouseModeDefaults.binding(for: .right, volumeScrollInverted: false) == .mouseMoveRight)
        #expect(MouseModeDefaults.binding(for: .ok, volumeScrollInverted: false) == .mouseLeftClick)
        #expect(MouseModeDefaults.binding(for: .menu, volumeScrollInverted: false) == .mouseRightClick)
    }

    @Test func volumeScrollInverts() {
        #expect(MouseModeDefaults.binding(for: .volumeUp, volumeScrollInverted: false) == .mouseScrollUp)
        #expect(MouseModeDefaults.binding(for: .volumeUp, volumeScrollInverted: true) == .mouseScrollDown)
        #expect(MouseModeDefaults.binding(for: .volumeDown, volumeScrollInverted: false) == .mouseScrollDown)
        #expect(MouseModeDefaults.binding(for: .volumeDown, volumeScrollInverted: true) == .mouseScrollUp)
    }

    /// 菜单键只占用单击这一个槽位；双击 / 长按 passthrough 到映射页。
    @Test func menuOnlyReservesSingleClick() {
        #expect(MouseModeDefaults.binding(for: .menu, trigger: .singleClick, volumeScrollInverted: false) == .mouseRightClick)
        #expect(MouseModeDefaults.binding(for: .menu, trigger: .doubleClick, volumeScrollInverted: false) == nil)
        #expect(MouseModeDefaults.binding(for: .menu, trigger: .longPress, volumeScrollInverted: false) == nil)
        #expect(MouseModeDefaults.isReserved(button: .menu, trigger: .singleClick, volumeScrollInverted: false))
        #expect(!MouseModeDefaults.isReserved(button: .menu, trigger: .doubleClick, volumeScrollInverted: false))
    }

    /// 方向键 / OK / 音量键整键占用（三个槽位都算占用）。
    @Test func wholeKeyReservedSlots() {
        for trigger in ButtonTrigger.allCases {
            #expect(MouseModeDefaults.binding(for: .up, trigger: trigger, volumeScrollInverted: false) == .mouseMoveUp)
            #expect(MouseModeDefaults.binding(for: .ok, trigger: trigger, volumeScrollInverted: false) == .mouseLeftClick)
            #expect(MouseModeDefaults.binding(for: .volumeUp, trigger: trigger, volumeScrollInverted: false) == .mouseScrollUp)
        }
    }

    @Test func unmappedButtonsPassThrough() {
        #expect(MouseModeDefaults.binding(for: .power, volumeScrollInverted: false) == nil)
        #expect(MouseModeDefaults.binding(for: .home, volumeScrollInverted: false) == nil)
        #expect(MouseModeDefaults.binding(for: .tv, volumeScrollInverted: false) == nil)
    }

    @Test func displacementSign() {
        // CGEvent 全局坐标 y 向下为正：上 = -y、下 = +y。
        #expect(MouseModeDefaults.displacement(for: .up, step: 10) == (0, -10))
        #expect(MouseModeDefaults.displacement(for: .down, step: 10) == (0, 10))
        #expect(MouseModeDefaults.displacement(for: .left, step: 10) == (-10, 0))
        #expect(MouseModeDefaults.displacement(for: .right, step: 10) == (10, 0))
    }

    // MARK: - 配置

    @Test func defaultConfigurationIsDisabled() {
        let config = MouseModeConfiguration()
        #expect(!config.enabled)
        #expect(config.toggle.button == .tv)
        #expect(config.toggle.trigger == .singleClick)
        #expect(config.acceleration.isValid)
    }

    @Test func accelerationInvalidWhenBaseExceedsMax() {
        var accel = MouseModeConfiguration.MouseAcceleration()
        accel.baseStep = 100
        accel.maxStep = 50
        #expect(!accel.isValid)
    }

    /// 光标外环颜色：nil=跟随系统；旧配置缺字段自然解码为 nil；非法输入不接管。
    @Test func cursorRingColorParsesHexAndRejectsInvalidValues() {
        #expect(MouseModeConfiguration.cursorRingColor(from: nil) == nil)
        #expect(MouseModeConfiguration.cursorRingColor(from: "") == nil)
        #expect(MouseModeConfiguration.cursorRingColor(from: "ZZZZZZ") == nil)
        #expect(MouseModeConfiguration.cursorRingColor(from: "0A84F") == nil)
        let color = MouseModeConfiguration.cursorRingColor(from: "0A84FF")
        let withHash = MouseModeConfiguration.cursorRingColor(from: "#0A84FF")
        #expect(color != nil)
        #expect(withHash != nil)
        #expect(MouseModeConfiguration.cursorRingHexString(from: color!) == "0A84FF")
        #expect(MouseModeConfiguration.cursorRingHexString(from: withHash!) == "0A84FF")
    }

    @Test func cursorRingColorPersistsAndLegacyConfigurationStaysOnSystemColor() throws {
        var config = MouseModeConfiguration()
        #expect(config.cursorRingColorHex == nil)
        config.cursorRingColorHex = "FF453A"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MouseModeConfiguration.self, from: data)
        #expect(decoded.cursorRingColorHex == "FF453A")

        let legacyJSON = """
        {"enabled":false,"toggle":{"button":"tv","trigger":"singleClick"},
         "volumeScrollInverted":false,
         "acceleration":{"baseStep":10,"acceleration":20,"maxStep":80,"stepInterval":16}}
        """
        let legacy = try JSONDecoder().decode(
            MouseModeConfiguration.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(legacy.cursorRingColorHex == nil)
    }

    @Test func cursorRingColorHasCompleteLocalizedCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for localization in ["zh-Hans", "en"] {
            let contents = try String(
                contentsOf: root.appendingPathComponent(
                    "Resources/\(localization).lproj/Localizable.strings"
                ),
                encoding: .utf8
            )
            for key in [
                "mouse_mode.cursor_ring.title",
                "mouse_mode.cursor_ring.subtitle",
                "mouse_mode.cursor_ring.custom",
                "mouse_mode.cursor_ring.follow_system",
            ] {
                #expect(contents.contains("\"\(key)\" ="))
            }
        }
    }

    // MARK: - 控制器解析

    @Test func resolveReturnsNilWhenFeatureDisabled() {
        let controller = MouseModeController()
        controller.apply(configuration: MouseModeConfiguration())
        // 功能关闭：所有键（含默认开关键 .tv）完全 passthrough，不接管。
        #expect(controller.resolve(.up, .singleClick) == nil)
        #expect(controller.resolve(.ok, .singleClick) == nil)
        #expect(controller.resolve(.tv, .singleClick) == nil)
    }

    @Test func resolveNoBuiltInToggleKey() {
        var config = MouseModeConfiguration()
        config.enabled = true
        config.toggle = MouseModeConfiguration.MouseModeToggle(button: .tv, trigger: .singleClick)
        let controller = MouseModeController()
        controller.apply(configuration: config)
        // 进入 / 退出只由「按键映射」页的「切换鼠标模式」动作触发，不再有内置开关键：
        // 未进入时完全 passthrough；进入后 TV 也只是普通键（由映射页决定）。
        #expect(controller.resolve(.tv, .singleClick) == nil)
        #expect(controller.resolve(.tv, .doubleClick) == nil)
        #expect(controller.resolve(.up, .singleClick) == nil)
        controller.setActive(true)
        #expect(controller.resolve(.tv, .singleClick) == nil)
    }

    @Test func resolveActiveMouseButtonsMappedRegardlessOfToggleConfig() {
        var config = MouseModeConfiguration()
        config.enabled = true
        config.toggle = MouseModeConfiguration.MouseModeToggle(button: .tv, trigger: .singleClick)
        let controller = MouseModeController()
        controller.apply(configuration: config)
        controller.setActive(true)
        // 激活时 TV 不再被特殊对待（不吞、不切换），由映射页决定；鼠标按键仍按固定映射。
        #expect(controller.resolve(.tv, .singleClick) == nil)
        #expect(controller.resolve(.ok, .singleClick) == .action(ConfiguredButtonAction(action: .mouseLeftClick, shortcut: nil)))
    }

    @Test func nonToggleKeyDoesNotToggleWhenInactive() {
        var config = MouseModeConfiguration()
        config.enabled = false
        config.toggle = MouseModeConfiguration.MouseModeToggle(button: .tv, trigger: .singleClick)
        let controller = MouseModeController()
        controller.apply(configuration: config)
        // 关闭时，开关键的非切换触发走原映射（resolve 返回 nil，由正常路径处理）。
        #expect(controller.resolve(.tv, .doubleClick) == nil)
    }

    @Test func resolveMapsMouseButtonsWhenActive() {
        var config = MouseModeConfiguration()
        config.enabled = true
        let controller = MouseModeController()
        controller.apply(configuration: config)
        controller.setActive(true)

        #expect(controller.resolve(.ok, .singleClick) == .action(ConfiguredButtonAction(action: .mouseLeftClick, shortcut: nil)))
        #expect(controller.resolve(.menu, .singleClick) == .action(ConfiguredButtonAction(action: .mouseRightClick, shortcut: nil)))
        #expect(controller.resolve(.up, .singleClick) == .action(ConfiguredButtonAction(action: .mouseMoveUp, shortcut: nil)))
        // 菜单只占单击：双击 / 长按 passthrough，走映射页自定义（切换就是绑在这里）。
        #expect(controller.resolve(.menu, .doubleClick) == nil)
        #expect(controller.resolve(.menu, .longPress) == nil)
        // 其他键 passthrough
        #expect(controller.resolve(.power, .singleClick) == nil)
    }

    // MARK: - 边缘处理

    @Test func edgeConsumesDirectionKeysOnlyWhenActive() {
        let controller = MouseModeController()
        controller.apply(configuration: MouseModeConfiguration()) // 关闭
        #expect(controller.edge(.up, .press) == false)

        var config = MouseModeConfiguration()
        config.enabled = true
        controller.apply(configuration: config)
        controller.setActive(true)

        #expect(controller.edge(.up, .press) == true)
        #expect(controller.edge(.up, .release) == true)
        // ok / menu 不是方向移动键，不被边缘消费（走单击触发路径）。
        #expect(controller.edge(.ok, .press) == false)
        #expect(controller.edge(.menu, .press) == false)
    }

    /// 回归：方向键 press 被 mouseModeEdgeHandler 消费后不会创建 Interaction，
    /// 所以 isTracking(button) 恒为 false。调用方（HIDRemoteMonitor 的 release 分支）
    /// 必须在 isTracking 门控之外独立把 release 交给同一个 edge handler，
    /// 否则 pressing 永不清空、加速定时器永不停——光标一按就冲到屏幕边缘。
    @Test func consumedEdgePressLeavesNoInteractionButReleaseIsStillAccepted() {
        let controller = RemoteButtonInteractionController(scheduler: DispatchHIDRemoteScheduler())
        var edgeReleases: [RemoteButton] = []
        controller.mouseModeEdgeHandler = { (button: RemoteButton, phase: RemoteButtonPhase) in
            if phase == .release { edgeReleases.append(button) }
            return true // 模拟鼠标模式激活且该键是方向键：press / release 都被消费
        }
        let snapshot = RemoteButtonInteractionSnapshot(
            settings: .init(), mode: .once,
            single: .init(action: .mouseMoveUp, shortcut: nil),
            double: .init(action: .disabled, shortcut: nil),
            long: .init(action: .disabled, shortcut: nil),
            allowsKeyHold: true
        )
        controller.handle(.press, button: .up, snapshot: snapshot, valid: { true },
                          perform: { _, _ in true })
        #expect(!controller.isTracking(.up)) // 消费路径没有创建 Interaction

        // 调用方独立转发 release（修复后的 HIDRemoteMonitor 行为）。
        let accepted = controller.mouseModeEdgeHandler?(.up, .release) == true
        #expect(accepted)
        #expect(edgeReleases == [.up])
    }

    @Test func buttonActionCategoryIsSystemAndMedia() {
        #expect(ButtonAction.mouseMoveUp.category == .systemAndMedia)
        #expect(ButtonAction.mouseLeftClick.category == .systemAndMedia)
        #expect(ButtonAction.mouseScrollDown.category == .systemAndMedia)
    }
}
