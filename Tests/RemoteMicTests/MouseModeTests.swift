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

    @Test func buttonActionCategoryIsSystemAndMedia() {
        #expect(ButtonAction.mouseMoveUp.category == .systemAndMedia)
        #expect(ButtonAction.mouseLeftClick.category == .systemAndMedia)
        #expect(ButtonAction.mouseScrollDown.category == .systemAndMedia)
    }
}
