import AppKit
import SwiftUI

/// 自定义模式设置页：创建 / 删除 / 重命名模式，为每个模式配置切换键、指示圈与独立按键映射。
///
/// 设计约定（独立一套映射，未设置的槽位回退普通模式）：
/// - 「普通模式」就是「按键」页的映射，不在本页管理。
/// - 每个自定义模式持有一张稀疏绑定表；表里没有的槽位运行时回退到普通映射。
/// - 切换键绑定在模式自身配置里，按它即可进入 / 退出该模式，与鼠标模式互斥。
struct CustomModesSettingsView: View {
    @ObservedObject var settings: AppSettings
    var localization: LocalizationStore

    @State private var selectedModeID: UUID?
    @State private var selectedButton: RemoteButton = .ok
    /// 正在编辑槽位动作的模式 ID + 槽位；非 nil 时弹出动作选择 Sheet。
    @State private var editingSlot: (modeID: UUID, button: RemoteButton, trigger: ButtonTrigger)?
    @State private var newModeName = ""

    private var config: Binding<CustomModeConfiguration> {
        $settings.customModeConfiguration
    }

    private var modes: [CustomMode] { settings.customModeConfiguration.modes }

    private var selectedMode: CustomMode? {
        guard let selectedModeID else { return modes.first }
        return modes.first { $0.id == selectedModeID }
    }

    private static let presetIndicatorColors = [
        "0A84FF", "FF453A", "30D158", "FF9F0A", "BF5AF2", "FFD60A",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modeListSection
                if let mode = selectedMode {
                    modeDetail(mode)
                } else {
                    emptyState
                }
            }
            .padding(24)
        }
        .onAppear {
            if selectedModeID == nil { selectedModeID = modes.first?.id }
        }
        .sheet(item: Binding(
            get: { editingSlot.map { SlotEditor(item: $0) } },
            set: { editingSlot = $0?.item }
        )) { editor in
            if let mode = modes.first(where: { $0.id == editor.item.modeID }) {
                ActionPickerSheet(
                    mode: mode,
                    button: editor.item.button,
                    trigger: editor.item.trigger,
                    localization: localization,
                    onPick: { action in
                        setAction(action, modeID: editor.item.modeID,
                                  button: editor.item.button, trigger: editor.item.trigger)
                        editingSlot = nil
                    },
                    onClear: {
                        setAction(nil, modeID: editor.item.modeID,
                                  button: editor.item.button, trigger: editor.item.trigger)
                        editingSlot = nil
                    },
                    onCancel: { editingSlot = nil }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.text("custom_mode.page.title"))
                .font(.system(size: 20, weight: .bold))
            Text(localization.text("custom_mode.page.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 模式列表

    private var modeListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("custom_mode.list.title"))
            HStack(spacing: 8) {
                TextField(localization.text("custom_mode.new.placeholder"), text: $newModeName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button(localization.text("custom_mode.new.button")) { addMode() }
                    .disabled(newModeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if modes.isEmpty {
                Text(localization.text("custom_mode.list.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(modes) { mode in
                            modeChip(mode)
                        }
                    }
                }
            }
        }
    }

    private func modeChip(_ mode: CustomMode) -> some View {
        Button {
            selectedModeID = mode.id
        } label: {
            HStack(spacing: 6) {
                if mode.showsIndicator {
                    Circle()
                        .fill(Color(nsColor: mode.indicatorColor ?? .controlAccentColor))
                        .frame(width: 10, height: 10)
                }
                Text(mode.name)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedMode?.id == mode.id
                          ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedMode?.id == mode.id ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        Text(localization.text("custom_mode.detail.empty"))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }

    // MARK: - 单模式详情

    private func modeDetail(_ mode: CustomMode) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            basicSection(mode)
            indicatorSection(mode)
            toggleSection(mode)
            mappingSection(mode)
        }
    }

    private func basicSection(_ mode: CustomMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("custom_mode.basic.title"))
            HStack(spacing: 10) {
                TextField(localization.text("custom_mode.name.placeholder"), text: nameBinding(mode))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button(role: .destructive) { removeMode(mode) } label: {
                    Text(localization.text("custom_mode.delete.button"))
                }
            }
        }
    }

    private func indicatorSection(_ mode: CustomMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("custom_mode.indicator.title"))
            Text(localization.text("custom_mode.indicator.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: indicatorEnabledBinding(mode)) {
                Text(localization.text("custom_mode.indicator.enable"))
                    .font(.system(size: 13, weight: .medium))
            }
            if mode.showsIndicator {
                HStack(spacing: 12) {
                    ColorPicker(
                        localization.text("custom_mode.indicator.custom"),
                        selection: indicatorColorBinding(mode)
                    )
                    .font(.system(size: 13))
                    Button(localization.text("custom_mode.indicator.follow_system")) {
                        setIndicatorColor(nil, modeID: mode.id)
                    }
                    .disabled(mode.indicatorColorHex == nil)
                }
                HStack(spacing: 8) {
                    ForEach(Self.presetIndicatorColors, id: \.self) { hex in
                        Button { setIndicatorColor(hex, modeID: mode.id) } label: {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: MouseModeConfiguration.cursorRingColor(from: hex) ?? .controlAccentColor))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(mode.indicatorColorHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
            }
        }
    }

    private func toggleSection(_ mode: CustomMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("custom_mode.toggle.title"))
            Text(localization.text("custom_mode.toggle.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Picker(localization.text("custom_mode.toggle.button"), selection: toggleButtonBinding(mode)) {
                    ForEach(RemoteButton.allCases) { button in
                        Text(button.displayName(using: localization)).tag(button as RemoteButton?)
                    }
                }
                .frame(maxWidth: 200)
                Picker(localization.text("custom_mode.toggle.trigger"), selection: toggleTriggerBinding(mode)) {
                    ForEach(ButtonTrigger.allCases) { trigger in
                        Text(trigger.displayName(using: localization)).tag(trigger as ButtonTrigger?)
                    }
                }
                .frame(maxWidth: 180)
            }
            if let toggle = mode.toggle,
               let conflict = conflictingModeID(mode, toggle: toggle) {
                Text(localization.text("custom_mode.toggle.conflict"))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mappingSection(_ mode: CustomMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.text("custom_mode.mapping.title"))
            Text(localization.text("custom_mode.mapping.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RemoteMappingCanvas(
                selectedButton: $selectedButton,
                activeButtons: [],
                voiceActive: false,
                remoteModel: settings.selectedRemoteProfile?.model,
                actionSummary: { button, trigger in slotSummary(mode: mode, button: button, trigger: trigger) },
                holdSummary: { _ in localization.text("button_mapping.hold.entry") },
                onEdit: { button, trigger in
                    editingSlot = (mode.id, button, trigger)
                },
                onEditHold: { _ in }
            )
        }
    }

    // MARK: - 槽位展示

    private func slotSummary(mode: CustomMode, button: RemoteButton, trigger: ButtonTrigger) -> String {
        if let toggle = mode.toggle, toggle.button == button, toggle.trigger == trigger {
            return localization.text("custom_mode.toggle.slot")
        }
        if let configured = mode.action(for: button, trigger: trigger),
           configured.action != .disabled {
            return configured.action.displayName(using: localization)
        }
        // 回退显示普通映射内容，和运行时行为一致。
        let base = settings.configuredAction(
            for: button, trigger: trigger, profileID: settings.selectedRemoteProfileID
        )
        let baseText = base.action == .disabled
            ? localization.text("button_mapping.action.not_set")
            : base.action.displayName(using: localization)
        return localization.text("custom_mode.slot.fallback") + baseText
    }

    // MARK: - 数据修改

    private func addMode() {
        let name = newModeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let mode = CustomMode(name: name)
        config.modes.wrappedValue.append(mode)
        selectedModeID = mode.id
        newModeName = ""
    }

    private func removeMode(_ mode: CustomMode) {
        config.modes.wrappedValue.removeAll { $0.id == mode.id }
        if selectedModeID == mode.id { selectedModeID = modes.first?.id }
    }

    private func setAction(_ action: ConfiguredButtonAction?, modeID: UUID,
                           button: RemoteButton, trigger: ButtonTrigger) {
        guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == modeID }) else { return }
        config.modes.wrappedValue[index].setAction(action, for: button, trigger: trigger)
    }

    private func setIndicatorColor(_ hex: String?, modeID: UUID) {
        guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == modeID }) else { return }
        config.modes.wrappedValue[index].indicatorColorHex = hex
    }

    private func conflictingModeID(_ mode: CustomMode, toggle: CustomModeToggle) -> UUID? {
        modes.first { other in
            other.id != mode.id && other.toggle?.button == toggle.button && other.toggle?.trigger == toggle.trigger
        }?.id
    }

    // MARK: - Bindings

    private func nameBinding(_ mode: CustomMode) -> Binding<String> {
        Binding(
            get: { mode.name },
            set: { newValue in
                guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == mode.id }) else { return }
                config.modes.wrappedValue[index].name = newValue
            }
        )
    }

    private func indicatorEnabledBinding(_ mode: CustomMode) -> Binding<Bool> {
        Binding(
            get: { mode.showsIndicator },
            set: { newValue in
                guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == mode.id }) else { return }
                config.modes.wrappedValue[index].showsIndicator = newValue
            }
        )
    }

    private func indicatorColorBinding(_ mode: CustomMode) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: mode.indicatorColor ?? .controlAccentColor) },
            set: { newColor in
                setIndicatorColor(
                    MouseModeConfiguration.cursorRingHexString(from: NSColor(newColor)),
                    modeID: mode.id
                )
            }
        )
    }

    private func toggleButtonBinding(_ mode: CustomMode) -> Binding<RemoteButton?> {
        Binding(
            get: { mode.toggle?.button },
            set: { button in
                guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == mode.id }) else { return }
                let trigger = mode.toggle?.trigger ?? .singleClick
                config.modes.wrappedValue[index].toggle = button.map {
                    CustomModeToggle(button: $0, trigger: trigger)
                }
            }
        )
    }

    private func toggleTriggerBinding(_ mode: CustomMode) -> Binding<ButtonTrigger?> {
        Binding(
            get: { mode.toggle?.trigger },
            set: { trigger in
                guard let index = config.modes.wrappedValue.firstIndex(where: { $0.id == mode.id }) else { return }
                let button = mode.toggle?.button ?? .ok
                config.modes.wrappedValue[index].toggle = trigger.map {
                    CustomModeToggle(button: button, trigger: $0)
                }
            }
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold))
    }
}

// MARK: - Sheet 辅助类型

private struct SlotEditor: Identifiable {
    let item: (modeID: UUID, button: RemoteButton, trigger: ButtonTrigger)
    var id: String { "\(item.modeID.uuidString)|\(item.button.rawValue)|\(item.trigger.rawValue)" }
}
