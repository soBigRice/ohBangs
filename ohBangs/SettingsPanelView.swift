import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(.system(size: 16, weight: .semibold))

            Toggle("通知提醒", isOn: $settings.notificationEnabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text("展示时长 \(Int(settings.previewDuration))s")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Slider(value: $settings.previewDuration, in: 2...8, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("延展宽度 \(Int(settings.expandWidth))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Slider(value: $settings.expandWidth, in: 220...320, step: 5)
            }

            Button("发送测试通知") {
                NotificationCenter.default.post(name: SystemNotificationBridge.triggerTestNotification, object: nil)
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, height: 220, alignment: .topLeading)
    }
}

#Preview {
    SettingsPanelView(settings: AppSettingsStore())
}
