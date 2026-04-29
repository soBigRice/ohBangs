import SwiftUI

struct SettingsPanelView: View {
    enum Mode {
        case panel
        case embedded
    }

    @ObservedObject var settings: AppSettingsStore
    let mode: Mode

    init(settings: AppSettingsStore, mode: Mode = .panel) {
        self.settings = settings
        self.mode = mode
    }

    var body: some View {
        Group {
            switch mode {
            case .panel:
                panelContent
            case .embedded:
                embeddedContent
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(.system(size: 16, weight: .semibold))

            sharedControls

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, height: 220, alignment: .topLeading)
    }

    private var embeddedContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("调整灵动岛通知与展开行为")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                HStack(spacing: 10) {
                    embeddedMetricCard(
                        title: "通知",
                        value: settings.notificationEnabled ? "开启" : "关闭",
                        detail: settings.notificationEnabled ? "允许岛内提醒" : "暂停弹出提醒",
                        accent: settings.notificationEnabled ? Color(red: 0.43, green: 0.86, blue: 0.53) : Color.white.opacity(0.55)
                    )

                    embeddedMetricCard(
                        title: "时长",
                        value: "\(Int(settings.previewDuration))s",
                        detail: "通知停留时间",
                        accent: Color(red: 0.70, green: 0.60, blue: 1.0)
                    )
                }

                embeddedToggleRow
                embeddedSliderRow(
                    title: "展示时长",
                    valueText: "\(Int(settings.previewDuration)) 秒",
                    value: $settings.previewDuration,
                    range: 2...8,
                    step: 1
                )
                embeddedSliderRow(
                    title: "延展宽度",
                    valueText: "\(Int(settings.expandWidth)) pt",
                    value: $settings.expandWidth,
                    range: 220...320,
                    step: 5
                )

                Button {
                    NotificationCenter.default.post(name: SystemNotificationBridge.triggerTestNotification, object: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                        Text("发送测试通知")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.38, blue: 0.92).opacity(0.85),
                                Color(red: 0.25, green: 0.43, blue: 0.98).opacity(0.75)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.045), Color.white.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var sharedControls: some View {
        Toggle("通知提醒", isOn: $settings.notificationEnabled)
            .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
            Text("展示时长 \(Int(settings.previewDuration))s")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mode == .panel ? Color.secondary : Color.white.opacity(0.68))
            Slider(value: $settings.previewDuration, in: 2...8, step: 1)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("延展宽度 \(Int(settings.expandWidth))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mode == .panel ? Color.secondary : Color.white.opacity(0.68))
            Slider(value: $settings.expandWidth, in: 220...320, step: 5)
        }

        Group {
            if mode == .panel {
                Button("发送测试通知") {
                    NotificationCenter.default.post(name: SystemNotificationBridge.triggerTestNotification, object: nil)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("发送测试通知") {
                    NotificationCenter.default.post(name: SystemNotificationBridge.triggerTestNotification, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var embeddedToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("通知提醒")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(settings.notificationEnabled ? "收到提醒时在岛内展示预览" : "暂停在岛内展示提醒")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $settings.notificationEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func embeddedSliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
            }

            Slider(value: value, in: range, step: step)
                .tint(Color(red: 0.52, green: 0.45, blue: 1.0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func embeddedMetricCard(
        title: String,
        value: String,
        detail: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    SettingsPanelView(settings: AppSettingsStore())
}
