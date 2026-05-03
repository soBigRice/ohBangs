import AppKit
import CoreLocation
import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsPanelView: View {
    enum Mode {
        case panel
        case embedded
    }

    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var weatherStore: WeatherStore
    let mode: Mode
    @State private var calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    init(settings: AppSettingsStore, weatherStore: WeatherStore, mode: Mode = .panel) {
        self.settings = settings
        self.weatherStore = weatherStore
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
        VStack(alignment: .leading, spacing: IslandSpacing.xLarge) {
            Text("设置")
                .font(.system(size: 16, weight: .semibold))

            sharedControls

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(
            minWidth: IslandLayout.settingsPanelMinWidth,
            idealWidth: IslandLayout.settingsPanelIdealWidth,
            maxWidth: IslandLayout.settingsPanelMaxWidth,
            minHeight: IslandLayout.settingsPanelMinHeight,
            alignment: .topLeading
        )
        .onAppear(perform: refreshPermissionStatus)
    }

    private var embeddedContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: IslandSpacing.large) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: IslandSpacing.xSmall) {
                        Text("设置")
                            .font(.system(size: IslandTypography.title, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("调整灵动岛通知与展开行为")
                            .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer(minLength: IslandSpacing.large)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                HStack(spacing: IslandSpacing.medium) {
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
                shortcutSettingsSection
                locationPermissionRow
                calendarPermissionRow

                Button {
                    NotificationCenter.default.post(name: SystemNotificationBridge.triggerTestNotification, object: nil)
                } label: {
                    HStack(spacing: IslandSpacing.medium) {
                        Image(systemName: "bell.badge")
                        Text("发送测试通知")
                    }
                    .font(.system(size: IslandTypography.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 34)
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
            .padding(IslandSpacing.xLarge)
            .padding(.bottom, IslandSpacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshPermissionStatus)
        .onChange(of: weatherStore.authorizationStatus) { _, newValue in
            locationAuthorizationStatus = newValue
        }
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

        VStack(alignment: .leading, spacing: IslandSpacing.small) {
            Text("展示时长 \(Int(settings.previewDuration))s")
                .font(.system(size: IslandTypography.body, weight: .medium))
                .foregroundStyle(mode == .panel ? Color.secondary : Color.white.opacity(0.68))
            Slider(value: $settings.previewDuration, in: 2...8, step: 1)
        }

        VStack(alignment: .leading, spacing: IslandSpacing.small) {
            Text("延展宽度 \(Int(settings.expandWidth))")
                .font(.system(size: IslandTypography.body, weight: .medium))
                .foregroundStyle(mode == .panel ? Color.secondary : Color.white.opacity(0.68))
            Slider(value: $settings.expandWidth, in: 220...320, step: 5)
        }

        shortcutSettingsSection

        Group {
            if mode == .panel {
                locationPermissionRow
                calendarPermissionRow
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

    private var locationPermissionRow: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.medium) {
            HStack(spacing: IslandSpacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("定位权限")
                        .font(.system(size: mode == .panel ? IslandTypography.body : 13, weight: .semibold))
                        .foregroundStyle(mode == .panel ? Color.primary : Color.white)

                    Text(locationPermissionDescription)
                        .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                        .foregroundStyle(mode == .panel ? Color.secondary : .white.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer(minLength: IslandSpacing.large)

                permissionToggle(isOn: locationPermissionEnabled, accent: locationPermissionAccent)
            }

            Button {
                openLocationPrivacySettings()
            } label: {
                HStack(spacing: IslandSpacing.small) {
                    Image(systemName: locationPermissionEnabled ? "location.fill" : "location.slash.fill")
                    Text(locationPermissionEnabled ? "管理定位权限" : "打开系统设置中的定位权限")
                }
                .font(.system(size: IslandTypography.body, weight: .semibold))
                .foregroundStyle(locationPermissionButtonForeground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
                .background(locationPermissionButtonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(locationPermissionButtonBorder, lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, mode == .panel ? 0 : IslandSpacing.large)
        .padding(.vertical, mode == .panel ? 0 : 10)
        .background(mode == .panel ? Color.clear : Color.white.opacity(0.04))
        .overlay {
            if mode != .panel {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var shortcutSettingsSection: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("快捷方式")
                        .font(.system(size: mode == .panel ? IslandTypography.body : 13, weight: .semibold))
                        .foregroundStyle(mode == .panel ? Color.primary : Color.white)

                    Text("勾选后会显示在快捷应用页，超出时可上下滚动。")
                        .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                        .foregroundStyle(mode == .panel ? Color.secondary : Color.white.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer(minLength: IslandSpacing.large)

                HStack(spacing: 8) {
                    Text("\(settings.pinnedShortcutIDs.count) 个")
                        .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                        .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.70, green: 0.60, blue: 1.0).opacity(mode == .panel ? 0.10 : 0.16))
                        .clipShape(Capsule())

                    Button {
                        pickCustomShortcutApp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("添加应用")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mode == .panel ? Color.primary : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(mode == .panel ? Color.black.opacity(0.05) : Color.white.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: IslandSpacing.medium),
                    GridItem(.flexible(), spacing: IslandSpacing.medium)
                ],
                spacing: IslandSpacing.medium
            ) {
                ForEach(settings.allShortcutOptions) { shortcut in
                    shortcutToggleCard(shortcut)
                }
            }
        }
        .padding(.horizontal, mode == .panel ? 0 : IslandSpacing.large)
        .padding(.vertical, mode == .panel ? 0 : 10)
        .background(mode == .panel ? Color.clear : Color.white.opacity(0.04))
        .overlay {
            if mode != .panel {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func shortcutToggleCard(_ shortcut: AppSettingsStore.ShortcutOption) -> some View {
        let isPinned = settings.isShortcutPinned(shortcut.id)

        return Button {
            settings.setShortcutPinned(shortcut.id, isPinned: !isPinned)
        } label: {
            HStack(spacing: IslandSpacing.medium) {
                Image(systemName: shortcut.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPinned ? shortcutAccentColor : shortcutMutedColor)
                    .frame(width: 28, height: 28)
                    .background((isPinned ? shortcutAccentColor : Color.white.opacity(0.08)).opacity(mode == .panel ? 0.12 : 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(shortcut.title)
                    .font(.system(size: mode == .panel ? IslandTypography.body : 12, weight: .semibold))
                    .foregroundStyle(mode == .panel ? Color.primary : .white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if !shortcut.isBuiltIn {
                        Button {
                            settings.removeCustomShortcut(id: shortcut.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red.opacity(mode == .panel ? 0.85 : 0.92))
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPinned ? shortcutAccentColor : shortcutMutedColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mode == .panel ? Color.black.opacity(0.03) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isPinned ? shortcutAccentColor.opacity(0.35) : Color.white.opacity(mode == .panel ? 0.08 : 0.05),
                        lineWidth: 0.8
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var shortcutAccentColor: Color {
        Color(red: 0.70, green: 0.60, blue: 1.0)
    }

    private var shortcutMutedColor: Color {
        mode == .panel ? Color.secondary : Color.white.opacity(0.42)
    }

    private func pickCustomShortcutApp() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加的应用"
        panel.message = "选择一个 .app 应用包，将它加入快捷方式列表。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        settings.addCustomShortcut(appURL: url)
    }

    private var calendarPermissionRow: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.medium) {
            HStack(spacing: IslandSpacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("日历权限")
                        .font(.system(size: mode == .panel ? IslandTypography.body : 13, weight: .semibold))
                        .foregroundStyle(mode == .panel ? Color.primary : Color.white)

                    Text(calendarPermissionDescription)
                        .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                        .foregroundStyle(mode == .panel ? Color.secondary : .white.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer(minLength: IslandSpacing.large)

                Text(calendarPermissionBadgeText)
                    .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                    .foregroundStyle(calendarPermissionAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(calendarPermissionAccent.opacity(mode == .panel ? 0.10 : 0.16))
                    .clipShape(Capsule())
            }

            Button {
                openCalendarPrivacySettings()
            } label: {
                HStack(spacing: IslandSpacing.small) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text("打开系统设置中的日历权限")
                }
                .font(.system(size: IslandTypography.body, weight: .semibold))
                .foregroundStyle(calendarPermissionButtonForeground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
                .background(calendarPermissionButtonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(calendarPermissionButtonBorder, lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, mode == .panel ? 0 : IslandSpacing.large)
        .padding(.vertical, mode == .panel ? 0 : 10)
        .background(mode == .panel ? Color.clear : Color.white.opacity(0.04))
        .overlay {
            if mode != .panel {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var calendarPermissionBadgeText: String {
        switch calendarAuthorizationStatus {
        case .fullAccess, .authorized:
            "已授权"
        case .writeOnly:
            "仅写入"
        case .notDetermined:
            "未决定"
        case .denied:
            "已拒绝"
        case .restricted:
            "受限制"
        @unknown default:
            "未知"
        }
    }

    private var calendarPermissionDescription: String {
        switch calendarAuthorizationStatus {
        case .fullAccess, .authorized:
            "已经允许读取系统日历，不会再重复请求。"
        case .writeOnly:
            "当前只有写入权限，仍然不能读取日历内容。"
        case .notDetermined:
            "首次访问时会请求完整权限，也可以先去系统设置手动开启。"
        case .denied, .restricted:
            "当前无法读取系统日历，需要去系统设置里手动授权。"
        @unknown default:
            "当前权限状态异常，建议前往系统设置检查。"
        }
    }

    private var calendarPermissionAccent: Color {
        switch calendarAuthorizationStatus {
        case .fullAccess, .authorized:
            .green
        case .writeOnly:
            .orange
        case .notDetermined:
            .yellow
        case .denied, .restricted:
            .red
        @unknown default:
            .gray
        }
    }

    private var calendarPermissionButtonForeground: Color {
        mode == .panel ? .primary : .white
    }

    private var calendarPermissionButtonBackground: Color {
        mode == .panel ? Color.black.opacity(0.06) : Color.white.opacity(0.04)
    }

    private var calendarPermissionButtonBorder: Color {
        mode == .panel ? Color.black.opacity(0.08) : Color.white.opacity(0.05)
    }

    private var locationPermissionEnabled: Bool {
        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            true
        default:
            false
        }
    }

    private var locationPermissionDescription: String {
        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "已允许读取当前位置，可以在灵动岛中展示实时天气。"
        case .notDetermined:
            "还没有决定是否授权定位，首次读取天气时会请求权限。"
        case .denied:
            "定位权限已关闭，需要前往系统设置手动开启。"
        case .restricted:
            "定位权限受系统限制，当前无法读取位置。"
        @unknown default:
            "定位权限状态异常，建议前往系统设置检查。"
        }
    }

    private var locationPermissionAccent: Color {
        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .green
        case .notDetermined:
            .yellow
        case .denied, .restricted:
            .red
        @unknown default:
            .gray
        }
    }

    private var locationPermissionButtonForeground: Color {
        mode == .panel ? .primary : .white
    }

    private var locationPermissionButtonBackground: Color {
        mode == .panel ? Color.black.opacity(0.06) : Color.white.opacity(0.04)
    }

    private var locationPermissionButtonBorder: Color {
        mode == .panel ? Color.black.opacity(0.08) : Color.white.opacity(0.05)
    }

    private func refreshPermissionStatus() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        locationAuthorizationStatus = weatherStore.authorizationStatus
    }

    private func openCalendarPrivacySettings() {
        refreshPermissionStatus()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openLocationPrivacySettings() {
        refreshPermissionStatus()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func permissionToggle(isOn: Bool, accent: Color) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? accent.opacity(mode == .panel ? 0.28 : 0.42) : Color.white.opacity(mode == .panel ? 0.18 : 0.12))
                .frame(width: 42, height: 24)

            Circle()
                .fill(.white.opacity(isOn ? 0.96 : 0.82))
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        }
    }

    private var embeddedToggleRow: some View {
        HStack(spacing: IslandSpacing.large) {
            VStack(alignment: .leading, spacing: 3) {
                Text("通知提醒")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(settings.notificationEnabled ? "收到提醒时在岛内展示预览" : "暂停在岛内展示提醒")
                    .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: IslandSpacing.large)

            Toggle("", isOn: $settings.notificationEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, IslandSpacing.large)
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
        VStack(alignment: .leading, spacing: IslandSpacing.medium) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: IslandSpacing.medium)

                Text(valueText)
                    .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
            }

            Slider(value: value, in: range, step: step)
                .tint(Color(red: 0.52, green: 0.45, blue: 1.0))
        }
        .padding(.horizontal, IslandSpacing.large)
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
                .font(.system(size: IslandTypography.caption, weight: .medium))
                .foregroundStyle(accent.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, IslandSpacing.large)
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
    SettingsPanelView(settings: AppSettingsStore(), weatherStore: WeatherStore())
}
