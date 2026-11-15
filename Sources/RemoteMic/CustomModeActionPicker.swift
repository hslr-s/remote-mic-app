import SwiftUI

/// 自定义模式槽位动作选择器：列出可独立配置的动作，选一个即写为该槽位的绑定。
///
/// 需要额外载荷的动作（自定义快捷键 / 组合动作 / 指定 App / App 内部动作）不在自定义模式里提供，
/// 保持本页自包含、不依赖「按键」页的录制状态机。
struct ActionPickerSheet: View {
    let mode: CustomMode
    let button: RemoteButton
    let trigger: ButtonTrigger
    var localization: LocalizationStore
    let onPick: (ConfiguredButtonAction) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var selectedAction: ButtonAction = .disabled

    private static let excluded: Set<ButtonAction> = [
        .customShortcut, .combinationAction, .openCustomApplication,
        .openCommonPhrases, .toggleLongRecording, .customModeToggle, .mouseModeToggle,
    ]
    private var availableActions: [ButtonAction] {
        ButtonAction.allCases.filter { !Self.excluded.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.text("custom_mode.action.title"))
                .font(.system(size: 16, weight: .bold))
            Text(localization.text("custom_mode.action.subtitle")
                 + " \(button.displayName(using: localization)) · \(trigger.displayName(using: localization))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let current = mode.action(for: button, trigger: trigger),
               current.action != .disabled {
                HStack {
                    Text(localization.text("custom_mode.action.current"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(localization.text("custom_mode.action.clear")) { onClear() }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(availableActions) { action in
                        Button {
                            selectedAction = action
                            onPick(ConfiguredButtonAction(action: action, shortcut: nil))
                        } label: {
                            HStack {
                                Text(action.displayName(using: localization))
                                    .font(.system(size: 13))
                                Spacer()
                                if selectedAction == action {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .frame(minHeight: 260, maxHeight: 420)
            HStack {
                Spacer()
                Button(localization.text("custom_mode.action.cancel")) { onCancel() }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            selectedAction = mode.action(for: button, trigger: trigger)?.action ?? .disabled
        }
    }
}
