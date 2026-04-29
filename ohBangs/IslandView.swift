import SwiftUI
import AppKit

private struct ScrollWheelCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = _ScrollWheelView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? _ScrollWheelView)?.onStep = onStep
    }

    private final class _ScrollWheelView: NSView {
        var onStep: ((Int) -> Void)?
        private var accumulated: CGFloat = 0
        private var lastFireAt: TimeInterval = 0
        private let threshold: CGFloat = 14

        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { self }

        override func scrollWheel(with event: NSEvent) {
            // Only react to horizontal scroll (trackpad two-finger swipe / shift+wheel).
            // Vertical scroll is intentionally ignored so up/down doesn't change the date.
            let dx = event.scrollingDeltaX
            guard abs(dx) > abs(event.scrollingDeltaY) else { return }
            accumulated += dx

            let now = event.timestamp
            guard now - lastFireAt > 0.05 else { return }

            while abs(accumulated) >= threshold {
                let step = accumulated > 0 ? 1 : -1
                onStep?(step)
                accumulated -= CGFloat(step) * threshold
                lastFireAt = now
            }

            if event.phase == .ended || event.momentumPhase == .ended {
                accumulated = 0
            }
        }
    }
}

private struct NotchShape: Shape, Animatable {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let tR = topCornerRadius
        let bR = bottomCornerRadius

        path.move(to: CGPoint(x: minX, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: minX + tR, y: minY + tR),
            control: CGPoint(x: minX + tR, y: minY)
        )
        path.addLine(to: CGPoint(x: minX + tR, y: maxY - bR))
        path.addQuadCurve(
            to: CGPoint(x: minX + tR + bR, y: maxY),
            control: CGPoint(x: minX + tR, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - tR - bR, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX - tR, y: maxY - bR),
            control: CGPoint(x: maxX - tR, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - tR, y: minY + tR))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY),
            control: CGPoint(x: maxX - tR, y: minY)
        )
        path.closeSubpath()
        return path
    }
}

enum IslandLayout {
    static let collapsedWidth: CGFloat = 185
    static let collapsedHeight: CGFloat = 32

    static let hintWidth: CGFloat = 270
    static let hintHeight: CGFloat = 50

    static let expandedWidth: CGFloat = 596
    static let expandedHeight: CGFloat = 218

    static let panelWidth: CGFloat = expandedWidth + 24
    static let panelHeight: CGFloat = expandedHeight + 16
}

struct IslandView: View {
    private enum ExpandedSection: String, CaseIterable, Identifiable {
        case calendar
        case cloudDrive
        case status
        case notification
        case overview
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "日历"
            case .cloudDrive: return "网盘"
            case .status: return "状态"
            case .notification: return "通知"
            case .overview: return "概览"
            case .settings: return "设置"
            }
        }

        var symbolName: String {
            switch self {
            case .calendar: return "calendar"
            case .cloudDrive: return "icloud"
            case .status: return "waveform.path.ecg"
            case .notification: return "bell.badge"
            case .overview: return "square.grid.2x2"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @ObservedObject var store: IslandStateStore
    @ObservedObject var settings: AppSettingsStore
    @Namespace private var sectionBarNamespace
    @State private var selectedSection: ExpandedSection = .calendar
    @State private var previousSection: ExpandedSection = .calendar
    @State private var presentedMonthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedCalendarEntryID: String?
    @State private var hoveredEntryID: String?
    @State private var hoveringCalendar: Bool = false

    private static let islandSpring: Animation =
        .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
    private static let sectionSwitchAnimation: Animation =
        .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    private let expandedContentAreaHeight: CGFloat = 130
    private let expandedSectionBarHeight: CGFloat = 34

    private var width: CGFloat {
        switch store.displayState {
        case .collapsed: return IslandLayout.collapsedWidth
        case .hint: return settings.expandWidth
        case .expanded: return IslandLayout.expandedWidth
        }
    }

    private var height: CGFloat {
        switch store.displayState {
        case .collapsed: return IslandLayout.collapsedHeight
        case .hint: return IslandLayout.hintHeight
        case .expanded: return IslandLayout.expandedHeight
        }
    }

    private var topR: CGFloat {
        switch store.displayState {
        case .collapsed: return 6
        case .hint: return 8
        case .expanded: return 14
        }
    }

    private var bottomR: CGFloat {
        switch store.displayState {
        case .collapsed: return 12
        case .hint: return 16
        case .expanded: return 22
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .fill(Color.black)

                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.04),
                                .white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
                    .opacity(store.isHovering ? 1 : 0)

                contentLayer
                    .frame(width: width, height: height, alignment: .top)
                    .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            }
            .frame(width: width, height: height)
            .contentShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .onHover { store.setHovering($0) }
            .onTapGesture {
                if !store.isExpanded {
                    store.expand()
                }
            }
            .contextMenu {
                Button("切换到设置") {
                    previousSection = selectedSection
                    selectedSection = .settings
                    store.expand()
                }
                Divider()
                Button(store.animationsEnabled ? "关闭动画" : "开启动画") {
                    store.toggleAnimations()
                }
                Divider()
                Button("开机启动（即将支持）") {}
                    .disabled(true)
                Button("显示屏选择（即将支持）") {}
                    .disabled(true)
            }
            .compositingGroup()
        }
        .frame(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight, alignment: .top)
        .animation(store.animationsEnabled ? Self.islandSpring : nil, value: store.displayState)
        .animation(store.animationsEnabled ? .easeOut(duration: 0.18) : nil, value: store.isHovering)
        .onAppear {
            syncSelectedCalendarEntry()
            syncPresentedMonthAnchor()
        }
        .onChange(of: store.currentContent.calendarOverview?.suggestedEntryID) { _, _ in
            syncSelectedCalendarEntry()
            syncPresentedMonthAnchor()
        }
        .onChange(of: selectedCalendarEntryID) { _, _ in
            syncPresentedMonthAnchor()
        }
        .accessibilityLabel("Dynamic Island")
        .accessibilityAddTraits(.isButton)
    }

    private var contentLayer: some View {
        ZStack {
            collapsedContent
                .opacity(store.isExpanded ? 0 : 1)
                .animation(store.animationsEnabled ? .easeOut(duration: store.isExpanded ? 0.10 : 0.20) : nil,
                           value: store.isExpanded)

            expandedContent
                .opacity(store.isExpanded ? 1 : 0)
                .animation(store.animationsEnabled ? .easeOut(duration: store.isExpanded ? 0.28 : 0.10)
                    .delay(store.isExpanded ? 0.08 : 0) : nil,
                           value: store.isExpanded)
        }
    }

    private var collapsedContent: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color(white: 0.20))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.55, opacity: 0.55), .clear],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 3, height: 3)
                    .offset(x: -1.5, y: -1.5)
            }
            .frame(width: 10, height: 10)
            Spacer().frame(width: 18)
        }
        .frame(height: IslandLayout.collapsedHeight)
        .allowsHitTesting(false)
    }

    private var expandedContent: some View {
        expandedMainContent
            .padding(.horizontal, 18)
            .padding(.top, 42)
            .padding(.bottom, 42)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private var expandedMainContent: some View {
        VStack(spacing: 10) {
            expandedSectionContent
                .id(selectedSection)
                .frame(height: expandedContentAreaHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .transition(sectionContentTransition)

            expandedSectionBar
                .frame(height: expandedSectionBarHeight)
                .offset(y: -12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var expandedSectionContent: some View {
        switch selectedSection {
        case .calendar:
            calendarBlock
        case .cloudDrive:
            cloudDrivePanel
        case .status:
            statusPanel
        case .notification:
            notificationPanel
        case .overview:
            overviewPanel
        case .settings:
            embeddedSettingsPanel
        }
    }

    private var expandedSectionBar: some View {
        HStack(spacing: 8) {
            ForEach(ExpandedSection.allCases) { section in
                Button {
                    guard selectedSection != section else { return }
                    previousSection = selectedSection
                    withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.symbolName)
                            .font(.system(size: 12, weight: .bold))
                        Text(section.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.56))
                    .frame(maxWidth: .infinity)
                    .frame(height: expandedSectionBarHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.015))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)

                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.14),
                                                Color(red: 0.42, green: 0.38, blue: 0.92).opacity(0.24)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                                    )
                                    .matchedGeometryEffect(id: "selectedSectionBackground", in: sectionBarNamespace)
                            }
                        }
                    }
                }
                .buttonStyle(IslandSegmentButtonStyle(isSelected: selectedSection == section))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.018), Color.white.opacity(0.008)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
        )
    }

    private var cloudDrivePanel: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.31, green: 0.58, blue: 1.0).opacity(0.18))

                Image(systemName: "icloud.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("快捷入口")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 8)

                    Text("iCloud")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1.0))
                }

                Text("iCloud 云盘")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("直接打开云盘，或者在默认位置快速新建文件夹。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    shortcutButton(title: "打开云盘", symbolName: "folder") {
                        openICloudDrive()
                    }

                    shortcutButton(title: "新建文件夹", symbolName: "folder.badge.plus") {
                        createFolderInICloudDrive()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var statusPanel: some View {
        detailPanel(
            symbolName: store.currentContent.isLive ? "dot.radiowaves.left.and.right" : "pause.circle",
            eyebrow: "实时状态",
            title: store.currentContent.title,
            subtitle: store.currentContent.appName,
            body: store.currentContent.subtitle,
            trailing: store.currentContent.isLive ? "LIVE" : "静态",
            accent: store.currentContent.isLive ? Color(red: 0.39, green: 0.62, blue: 1.0) : Color.white.opacity(0.75)
        )
    }

    private var notificationPanel: some View {
        let preview = store.notificationPreview

        return detailPanel(
            symbolName: preview?.iconSystemName ?? "bell.slash",
            eyebrow: "通知预览",
            title: preview?.title ?? "当前没有通知",
            subtitle: preview == nil ? "等待系统通知进入岛内" : "来自系统桥接",
            body: preview?.subtitle ?? "收到通知后，这里会展示标题和副标题。",
            trailing: preview == nil ? "空闲" : "新消息",
            accent: preview == nil ? Color.white.opacity(0.75) : Color(red: 0.96, green: 0.73, blue: 0.27)
        )
    }

    private var overviewPanel: some View {
        HStack(spacing: 12) {
            overviewMetric(title: "来源", value: store.currentContent.appName, emphasis: false)
            overviewMetric(title: "模式", value: store.currentContent.isLive ? "实时" : "静态", emphasis: true)
            overviewMetric(title: "已展开", value: "\(calendarEntries.count) 天", emphasis: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var embeddedSettingsPanel: some View {
        SettingsPanelView(settings: settings, mode: .embedded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailPanel(
        symbolName: String,
        eyebrow: String,
        title: String,
        subtitle: String,
        body: String,
        trailing: String,
        accent: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 8)

                    Text(trailing)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func shortcutButton(title: String, symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(0.10))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(IslandShortcutButtonStyle())
    }

    private func overviewMetric(title: String, value: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: emphasis ? 24 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("通过底部按钮切换容器内容")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var calendarBlock: some View {
        HStack(alignment: .top, spacing: 0) {
            calendarSummaryColumn

            calendarDivider

            calendarMonthColumn

            calendarDivider

            calendarAgendaColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ScrollWheelCatcher { step in
                moveCalendarSelection(forward: step > 0)
            }
            .allowsHitTesting(true)
        )
        .gesture(calendarSwipeGesture)
        .onHover { hovering in
            hoveringCalendar = hovering
        }
    }

    private var calendarSummaryColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                calendarDateBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCalendarDate?.formatted(.dateTime.year()) ?? "日历")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                        .lineLimit(1)

                    Text(selectedCalendarDate.map(fullWeekdayLabel(for:)) ?? "系统日历")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    calendarWeatherPill
                }
            }

            calendarFeaturedEventCard
        }
        .padding(.trailing, 7)
        .padding(.top, 4)
        .frame(width: 152)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var calendarDateBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.20, blue: 0.50),
                            Color(red: 0.25, green: 0.43, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )

            VStack(spacing: 1) {
                Text(selectedCalendarDate?.formatted(.dateTime.month(.abbreviated)) ?? "APR")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(selectedCalendarEntry?.dayText ?? "--")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 42, height: 42)
    }

    private var calendarWeatherPill: some View {
        let detail = selectedCalendarEntry?.detail ?? placeholderDetail
        let accent = selectedCalendarEntry?.hasEvents == true
            ? Color(red: 1.0, green: 0.64, blue: 0.28)
            : Color(red: 0.43, green: 0.86, blue: 0.53)

        return HStack(spacing: 6) {
            Image(systemName: selectedCalendarEntry?.hasEvents == true ? "sun.max.fill" : "sparkles")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)

            Text(detail.statusText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            Text(detail.timeText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(Color.white.opacity(0.05))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .clipShape(Capsule())
    }

    private var calendarFeaturedEventCard: some View {
        let detail = selectedCalendarEntry?.detail ?? placeholderDetail
        let accent = accentColor(for: selectedCalendarEntry)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)

                Text(detail.timeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 4)

                Text(calendarStatusBadgeText(for: selectedCalendarEntry))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            Text(detail.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(calendarMetaText(for: selectedCalendarEntry))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
        }
        .padding(6)
        .frame(height: 50, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.058),
                            Color.white.opacity(0.028)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
    }

    private var calendarMonthColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                monthNavigationButton(systemName: "chevron.left") {
                    shiftPresentedMonth(by: -1)
                }

                Text(presentedMonthAnchor.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .frame(maxWidth: .infinity, alignment: .center)

                monthNavigationButton(systemName: "chevron.right") {
                    shiftPresentedMonth(by: 1)
                }
            }

            calendarWeekHeader

            calendarMonthGrid
        }
        .padding(.horizontal, 7)
        .padding(.top, 4)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func monthNavigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(IslandShortcutButtonStyle())
    }

    private var calendarWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(compactWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarMonthGrid: some View {
        let days = monthGridDays

        return VStack(spacing: 1) {
            ForEach(0..<days.count / 7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        calendarMonthDayCell(day)
                    }
                }
            }
        }
    }

    private func calendarMonthDayCell(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isInMonth = calendar.isDate(date, equalTo: presentedMonthAnchor, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let entry = entry(for: date)
        let isSelected = selectedCalendarDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let dotColor = accentColor(for: entry)

        return Button {
            if let entry {
                withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                    selectedCalendarEntryID = entry.id
                }
            }
        } label: {
            ZStack(alignment: .bottom) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: isSelected ? 9 : 8, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(
                        isSelected ? Color.white :
                            (isInMonth ? Color.white.opacity(isToday ? 0.95 : 0.78) : Color.white.opacity(0.22))
                    )
                    .frame(width: 15, height: 15)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.58, green: 0.44, blue: 1.0), Color(red: 0.41, green: 0.34, blue: 0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }

                if entry?.hasEvents == true {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 1.5, height: 1.5)
                        .offset(y: 1)
                } else if isToday {
                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 1.5, height: 1.5)
                        .offset(y: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry == nil)
    }

    private var calendarAgendaColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日安排")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text("\(agendaEntries.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Color(red: 0.42, green: 0.38, blue: 0.92).opacity(0.14))
                    .clipShape(Capsule())

                Spacer(minLength: 8)

                Button {
                    jumpToTodayCalendarEntry()
                } label: {
                    HStack(spacing: 6) {
                        Text("今天")
                        Image(systemName: "calendar")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(IslandShortcutButtonStyle())
            }

            VStack(spacing: 5) {
                ForEach(displayedAgendaEntries) { entry in
                    agendaEventCard(entry)
                }
            }
        }
        .padding(.leading, 9)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agendaEventCard(_ entry: IslandContent.CalendarDayEntry) -> some View {
        let detail = entry.detail
        let accent = accentColor(for: entry)
        let isSelected = entry.id == selectedCalendarEntry?.id

        return Button {
            withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                selectedCalendarEntryID = entry.id
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.timeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)

                    Text(detail.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(calendarMetaText(for: entry))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(calendarStatusBadgeText(for: entry))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.62))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background((isSelected ? accent.opacity(0.16) : Color.white.opacity(0.05)))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    accent.opacity(0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.045),
                                    Color.white.opacity(0.025)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.11 : 0.05), lineWidth: 0.8)
            )
        }
        .buttonStyle(IslandShortcutButtonStyle())
    }

    private var calendarEntries: [IslandContent.CalendarDayEntry] {
        store.currentContent.calendarOverview?.entries ?? fallbackCalendarEntries
    }

    private var agendaEntries: [IslandContent.CalendarDayEntry] {
        let events = calendarEntries.filter(\.hasEvents)
        return events.isEmpty ? Array(calendarEntries.prefix(3)) : Array(events.prefix(3))
    }

    private var displayedAgendaEntries: [IslandContent.CalendarDayEntry] {
        let hasRealEvents = agendaEntries.contains(where: \.hasEvents)
        return Array(agendaEntries.prefix(hasRealEvents ? 2 : 1))
    }

    private var selectedCalendarEntry: IslandContent.CalendarDayEntry? {
        if let selectedCalendarEntryID,
           let match = calendarEntries.first(where: { $0.id == selectedCalendarEntryID }) {
            return match
        }
        return calendarEntries.first
    }

    private var selectedCalendarDate: Date? {
        guard let selectedCalendarEntry else { return nil }
        return calendarDate(from: selectedCalendarEntry.id)
    }

    private var monthGridDays: [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: presentedMonthAnchor))
            ?? presentedMonthAnchor
        let weekday = calendar.component(.weekday, from: monthStart)
        let mondayBasedWeekday = (weekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -mondayBasedWeekday, to: monthStart) ?? monthStart
        return (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var compactWeekdaySymbols: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    private var placeholderDetail: IslandContent.CalendarEventDetail {
        IslandContent.CalendarEventDetail(
            title: store.currentContent.title,
            timeText: store.currentContent.subtitle,
            detailText: "正在准备日历内容",
            statusText: "同步中",
            symbolName: "calendar",
            isPlaceholder: true
        )
    }

    private var fallbackCalendarEntries: [IslandContent.CalendarDayEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return IslandContent.CalendarDayEntry(
                id: day.formatted(.iso8601.year().month().day()),
                monthText: day.formatted(.dateTime.month(.defaultDigits)) + "月",
                dayText: day.formatted(.dateTime.day()),
                weekdayText: compactWeekdayLabel(for: day),
                isToday: offset == 0,
                hasEvents: offset == 0,
                detail: placeholderDetail
            )
        }
    }

    private var calendarSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -24 {
                    moveCalendarSelection(forward: true)
                } else if value.translation.width > 24 {
                    moveCalendarSelection(forward: false)
                }
            }
    }

    private func moveCalendarSelection(forward: Bool) {
        guard let current = selectedCalendarEntry,
              let index = calendarEntries.firstIndex(where: { $0.id == current.id }) else {
            syncSelectedCalendarEntry()
            return
        }

        let targetIndex = forward ? min(index + 1, calendarEntries.count - 1) : max(index - 1, 0)
        selectedCalendarEntryID = calendarEntries[targetIndex].id
    }

    private func syncSelectedCalendarEntry() {
        guard let overview = store.currentContent.calendarOverview else {
            selectedCalendarEntryID = nil
            return
        }

        if let selectedCalendarEntryID,
           overview.entries.contains(where: { $0.id == selectedCalendarEntryID }) {
            return
        }

        selectedCalendarEntryID = overview.suggestedEntryID
    }

    private func syncPresentedMonthAnchor() {
        presentedMonthAnchor = selectedCalendarDate ?? Calendar.current.startOfDay(for: Date())
    }

    private func shiftPresentedMonth(by delta: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: delta, to: presentedMonthAnchor) else { return }
        withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
            presentedMonthAnchor = shifted
        }
    }

    private func jumpToTodayCalendarEntry() {
        if let todayEntry = calendarEntries.first(where: \.isToday) {
            withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                selectedCalendarEntryID = todayEntry.id
            }
        } else {
            withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                presentedMonthAnchor = Calendar.current.startOfDay(for: Date())
            }
        }
    }

    private func entry(for date: Date) -> IslandContent.CalendarDayEntry? {
        calendarEntries.first { entry in
            guard let entryDate = calendarDate(from: entry.id) else { return false }
            return Calendar.current.isDate(entryDate, inSameDayAs: date)
        }
    }

    private func calendarDate(from id: String) -> Date? {
        Self.calendarEntryDateFormatter.date(from: id)
    }

    private func fullWeekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let labels = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return labels[max(0, min(labels.count - 1, weekday - 1))]
    }

    private func compactWeekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return labels[max(0, min(labels.count - 1, weekday - 1))]
    }

    private func accentColor(for entry: IslandContent.CalendarDayEntry?) -> Color {
        guard let entry else { return Color.white.opacity(0.32) }
        if entry.detail.statusText == "进行中" {
            return Color(red: 0.62, green: 0.50, blue: 1.0)
        }
        return entry.hasEvents
            ? Color(red: 0.37, green: 0.62, blue: 1.0)
            : Color(red: 0.31, green: 0.88, blue: 0.54)
    }

    private func calendarMetaText(for entry: IslandContent.CalendarDayEntry?) -> String {
        guard let entry else { return "暂无事件详情" }
        let weekday = calendarDate(from: entry.id).map(fullWeekdayLabel(for:)) ?? "日历"
        return "\(weekday) · \(entry.detail.detailText)"
    }

    private func calendarStatusBadgeText(for entry: IslandContent.CalendarDayEntry?) -> String {
        guard let entry else { return "空闲" }
        return entry.isToday ? (entry.hasEvents ? "今天" : "空闲") : entry.detail.statusText
    }

    private var calendarDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.01), Color.white.opacity(0.08), Color.white.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private func openICloudDrive() {
        if let ubiquitousURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .deletingLastPathComponent() {
            NSWorkspace.shared.open(ubiquitousURL)
            return
        }

        let mobileDocumentsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Mobile Documents")
        NSWorkspace.shared.open(mobileDocumentsURL)
    }

    private func createFolderInICloudDrive() {
        let fileManager = FileManager.default
        let baseURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
            .deletingLastPathComponent()
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library")
                .appending(path: "Mobile Documents")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderURL = baseURL.appending(path: "ohBangs-\(formatter.string(from: Date()))")

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        } catch {
            NSSound.beep()
        }
    }

    private static let calendarEntryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var sectionContentTransition: AnyTransition {
        let movingForward = selectedSectionIndex >= previousSectionIndex
        let insertionOffset = movingForward ? 20.0 : -20.0
        let removalOffset = movingForward ? -14.0 : 14.0

        return .asymmetric(
            insertion: .offset(x: insertionOffset).combined(with: .opacity),
            removal: .offset(x: removalOffset).combined(with: .opacity)
        )
    }

    private var selectedSectionIndex: Int {
        ExpandedSection.allCases.firstIndex(of: selectedSection) ?? 0
    }

    private var previousSectionIndex: Int {
        ExpandedSection.allCases.firstIndex(of: previousSection) ?? 0
    }
}

private struct IslandSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : (isSelected ? 1.0 : 0.985))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct IslandShortcutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview("Collapsed") {
    IslandView(store: {
        let s = IslandStateStore()
        s.collapse()
        return s
    }(), settings: AppSettingsStore())
    .padding(40)
    .background(
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.52, blue: 0.70),
                     Color(red: 0.20, green: 0.36, blue: 0.56)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#Preview("Expanded") {
    IslandView(store: {
        let s = IslandStateStore()
        s.expand()
        return s
    }(), settings: AppSettingsStore())
    .padding(40)
    .background(
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.52, blue: 0.70),
                     Color(red: 0.20, green: 0.36, blue: 0.56)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
