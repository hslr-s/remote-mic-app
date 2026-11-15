import SwiftUI

/// 鼠标模式设置页：独立侧栏分区，不进入动作分类筛选。
///
/// v1 只暴露：总开关、启用键、音量滚轮互换、加速参数；方向 / 确认 / 菜单映射写死并以锁定样式展示。
/// 编辑其他键映射留待 v2（见 `feature/mouse-mode/PRODUCT_SPEC.md`）。
struct MouseModeSettingsView: View {
    @ObservedObject var settings: AppSettings
    var localization: LocalizationStore

    private var config: Binding<MouseModeConfiguration> {
        $settings.mouseModeConfiguration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                enableSection
                toggleSection
                scrollSection
                accelerationSection
                fixedMappingSection
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

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.toggle.title"))
            Text(localization.text("mouse_mode.toggle.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

    private var fixedMappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("mouse_mode.fixed.title"))
            Text(localization.text("mouse_mode.fixed.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(MouseModeDefaults.mouseButtons), id: \.self) { button in
                    HStack {
                        Text(remoteButtonName(button))
                            .font(.system(size: 13))
                        Spacer()
                        Text(actionName(for: button))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
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

    private func remoteButtonName(_ button: RemoteButton) -> String {
        let key = "remote_button.\(button.rawValue)"
        let localized = localization.text(key)
        return localized == key ? button.rawValue : localized
    }

    private func buttonTriggerName(_ trigger: ButtonTrigger) -> String {
        let key = "button_trigger.\(trigger.rawValue)"
        let localized = localization.text(key)
        return localized == key ? trigger.rawValue : localized
    }

    private func actionName(for button: RemoteButton) -> String {
        guard let action = MouseModeDefaults.binding(
            for: button,
            volumeScrollInverted: settings.mouseModeConfiguration.volumeScrollInverted
        ) else {
            return ""
        }
        return action.displayName(using: localization)
    }
}
