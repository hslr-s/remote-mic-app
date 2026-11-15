import SwiftUI

/// 鼠标模式设置页：顶部为模式参数，下方复用按键映射画布做「只读预览」。
///
/// 双模式约定（见 `feature/mouse-mode/PRODUCT_SPEC.md`）：
/// - 普通模式 = 「按键」页，全部槽位可自定义，任意「键 + 触发」都可绑为「切换鼠标模式」。
/// - 鼠标模式 = 本页；被占用槽位显示鼠标固定功能并置灰，未占用槽位显示映射页设置，整体只读。
struct MouseModeSettingsView: View {
    @ObservedObject var settings: AppSettings
    var localization: LocalizationStore

    @State private var selectedButton: RemoteButton = .up

    private var config: Binding<MouseModeConfiguration> {
        $settings.mouseModeConfiguration
    }

    private var inverted: Bool { settings.mouseModeConfiguration.volumeScrollInverted }
    private var profileID: UUID? { settings.selectedRemoteProfileID }

    private static let presetRingColors = [
        "0A84FF", "FF453A", "30D158", "FF9F0A", "BF5AF2", "FFD60A",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                enableSection
                cursorRingSection
                toggleSection
                mappingPreviewSection
                scrollSection
                accelerationSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.text("settings.section.mouse_mode"))
                .font(.system(size: 20, weight: .bold))
            Text(localization.text("mouse_mode.page.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var enableSection: some View {
        Toggle(isOn: config.enabled) {
            Text(localization.text("mouse_mode.enable.title"))
                .font(.system(size: 13, weight: .medium))
        }
        .help(localization.text("mouse_mode.enable.help"))
    }

    /// 光标外环圈颜色：`nil` 跟随系统强调色；预设色板 + 自定义 ColorPicker。
    private var cursorRingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.cursor_ring.title"))
            Text(localization.text("mouse_mode.cursor_ring.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ColorPicker(
                    localization.text("mouse_mode.cursor_ring.custom"),
                    selection: ringColorBinding
                )
                .font(.system(size: 13))
                Button(localization.text("mouse_mode.cursor_ring.follow_system")) {
                    config.cursorRingColorHex.wrappedValue = nil
                }
                .disabled(config.cursorRingColorHex.wrappedValue == nil)
            }
            HStack(spacing: 8) {
                ForEach(Self.presetRingColors, id: \.self) { hex in
                    Button {
                        config.cursorRingColorHex.wrappedValue = hex
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: MouseModeConfiguration.cursorRingColor(from: hex) ?? .controlAccentColor))
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(
                                        config.cursorRingColorHex.wrappedValue == hex
                                            ? Color.primary : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                    .accessibilityLabel(hex)
                }
            }
        }
    }

    private var ringColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let ns = MouseModeConfiguration.cursorRingColor(
                    from: config.cursorRingColorHex.wrappedValue
                ) else {
                    return Color(nsColor: .controlAccentColor)
                }
                return Color(nsColor: ns)
            },
            set: { newColor in
                config.cursorRingColorHex.wrappedValue = MouseModeConfiguration.cursorRingHexString(
                    from: NSColor(newColor)
                )
            }
        )
    }

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.toggle.title"))
            Text(localization.text("mouse_mode.toggle.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 与「按键」页同款的遥控器画布，整体只读：
    /// 占用槽位（含切换槽位）置灰加锁，未占用槽位显示映射页设置。
    private var mappingPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.mapping.title"))
            Text(localization.text("mouse_mode.mapping.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RemoteMappingCanvas(
                selectedButton: $selectedButton,
                activeButtons: [],
                voiceActive: false,
                remoteModel: settings.selectedRemoteProfile?.model,
                actionSummary: { button, trigger in slotSummary(button: button, trigger: trigger) },
                holdSummary: { button in holdSummary(button: button) },
                onEdit: { _, _ in },
                onEditHold: { _ in },
                onVoiceSettings: {},
                isSlotLocked: { button, trigger in isSlotLocked(button: button, trigger: trigger) },
                isHoldLocked: { button in MouseModeDefaults.movedButtons.contains(button) }
            )
        }
    }

    private var scrollSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.scroll.title"))
            Text(localization.text("mouse_mode.scroll.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Toggle(isOn: config.volumeScrollInverted) {
                Text(localization.text("mouse_mode.scroll.invert"))
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var accelerationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.acceleration.title"))
            Text(localization.text("mouse_mode.acceleration.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            labelledStepper(
                localization.text("mouse_mode.acceleration.base_step"),
                value: config.acceleration.baseStep,
                range: 1...200,
                step: 1,
                unit: "px"
            )
            labelledStepper(
                localization.text("mouse_mode.acceleration.slope"),
                value: config.acceleration.acceleration,
                range: 0...200,
                step: 1,
                unit: "px/s"
            )
            labelledStepper(
                localization.text("mouse_mode.acceleration.max_step"),
                value: config.acceleration.maxStep,
                range: 1...400,
                step: 1,
                unit: "px"
            )
            labelledStepper(
                localization.text("mouse_mode.acceleration.interval"),
                value: config.acceleration.stepInterval,
                range: 1...100,
                step: 1,
                unit: "ms"
            )
        }
    }

    // MARK: - 槽位展示（与运行时 MouseModeDefaults 同一套占用规则）

    /// 映射页里绑定了「切换鼠标模式」的全部槽位。
    private var toggleSlots: Set<String> {
        var result = Set<String>()
        for button in RemoteButton.allCases {
            for trigger in ButtonTrigger.allCases {
                let configured = settings.configuredAction(
                    for: button, trigger: trigger, profileID: profileID
                )
                if configured.action == .mouseModeToggle {
                    result.insert(slotKey(button, trigger))
                }
            }
        }
        return result
    }

    private func slotKey(_ button: RemoteButton, _ trigger: ButtonTrigger) -> String {
        "\(button.rawValue)|\(trigger.rawValue)"
    }

    private func isSlotLocked(button: RemoteButton, trigger: ButtonTrigger) -> Bool {
        if toggleSlots.contains(slotKey(button, trigger)) { return true }
        return MouseModeDefaults.isReserved(
            button: button, trigger: trigger, volumeScrollInverted: inverted
        )
    }

    private func slotSummary(button: RemoteButton, trigger: ButtonTrigger) -> String {
        if toggleSlots.contains(slotKey(button, trigger)) {
            return localization.text("action.mouse_mode_toggle")
        }
        if let fixed = MouseModeDefaults.binding(
            for: button, trigger: trigger, volumeScrollInverted: inverted
        ) {
            return fixed.displayName(using: localization)
        }
        return mappingSummary(for: button, trigger: trigger)
    }

    /// 未占用槽位显示「按键映射」页里设置的内容。
    private func mappingSummary(for button: RemoteButton, trigger: ButtonTrigger) -> String {
        let configured = settings.configuredAction(
            for: button, trigger: trigger, profileID: profileID
        )
        guard configured.action != .disabled else {
            return localization.text("button_mapping.action.not_set")
        }
        return configured.action.displayName(using: localization)
    }

    private func holdSummary(button: RemoteButton) -> String {
        if MouseModeDefaults.movedButtons.contains(button) {
            return localization.text("mouse_mode.hold.accelerate")
        }
        return localization.text("button_mapping.hold.entry")
    }

    // MARK: - 小组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
    }

    private func labelledStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        Stepper(
            value: value,
            in: range,
            step: step
        ) {
            Text("\(title)：\(value.wrappedValue) \(unit)")
                .font(.system(size: 13))
        }
    }
}
