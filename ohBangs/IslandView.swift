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
    static let hintHeight: CGFloat = 50

    static let expandedMinWidth: CGFloat = 520
    static let expandedIdealWidth: CGFloat = 596
    static let expandedMaxWidth: CGFloat = 680
    static let expandedMinHeight: CGFloat = 218
    static let expandedMaxHeight: CGFloat = 252

    static let panelHorizontalPadding: CGFloat = 12
    static let panelVerticalPadding: CGFloat = 8

    static let settingsPanelMinWidth: CGFloat = 320
    static let settingsPanelIdealWidth: CGFloat = 360
    static let settingsPanelMaxWidth: CGFloat = 420
    static let settingsPanelMinHeight: CGFloat = 286

    static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    static func expandedWidth(for availableWidth: CGFloat) -> CGFloat {
        clamp(min(availableWidth, expandedIdealWidth), min: expandedMinWidth, max: expandedIdealWidth)
    }

    static func expandedHeight(for expandedWidth: CGFloat) -> CGFloat {
        clamp(expandedWidth * 0.37, min: expandedMinHeight, max: expandedMaxHeight)
    }

    static func panelSize(for screen: NSScreen?) -> NSSize {
        let availableScreenWidth = max((screen?.visibleFrame.width ?? 1440) - 64, expandedMinWidth)
        let expandedWidth = expandedWidth(for: availableScreenWidth)
        let expandedHeight = expandedHeight(for: expandedWidth)

        return NSSize(
            width: expandedWidth + panelHorizontalPadding * 2,
            height: expandedHeight + panelVerticalPadding * 2
        )
    }

    static func expandedIslandSize(in panelSize: CGSize) -> CGSize {
        CGSize(
            width: max(panelSize.width - panelHorizontalPadding * 2, collapsedWidth),
            height: max(panelSize.height - panelVerticalPadding * 2, expandedMinHeight)
        )
    }
}

enum IslandSpacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 6
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let xLarge: CGFloat = 14
    static let xxLarge: CGFloat = 18
}

enum IslandTypography {
    static let caption: CGFloat = 10
    static let body: CGFloat = 12
    static let eyebrow: CGFloat = 11
    static let title: CGFloat = 18
    static let metric: CGFloat = 24
}

struct IslandView: View {
    private struct StatusMetrics {
        let scale: CGFloat
        let cardSpacing: CGFloat
        let horizontalInset: CGFloat
        let verticalInset: CGFloat
        let leftWidth: CGFloat
        let rightWidth: CGFloat
        let metricWidth: CGFloat
        let rightCardHeight: CGFloat
        let metricCardHeight: CGFloat
        let sectionHeaderHeight: CGFloat
    }

    private struct CalendarMetrics {
        let scale: CGFloat
        let summaryWidth: CGFloat
        let monthWidth: CGFloat
        let badgeSize: CGFloat
        let pillHeight: CGFloat
        let navButtonSize: CGFloat
        let featuredCardMinHeight: CGFloat
        let agendaCardMinHeight: CGFloat
        let calendarCellSize: CGFloat
        let dotSize: CGFloat
        let badgeHeight: CGFloat
    }

    private struct ExpandedLayoutMetrics {
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let sectionSpacing: CGFloat
        let contentHorizontalPadding: CGFloat
        let contentVerticalPadding: CGFloat
        let cardPadding: CGFloat
        let cardInnerSpacing: CGFloat
    }

    fileprivate enum ExpandedSection: String, CaseIterable, Identifiable {
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
    @State private var selectedSection: ExpandedSection
    @State private var previousSection: ExpandedSection
    @State private var presentedMonthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedCalendarEntryID: String?
    @State private var hoveredEntryID: String?
    @State private var hoveringCalendar: Bool = false

    private static let islandSpring: Animation =
        .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
    private static let sectionSwitchAnimation: Animation =
        .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    private let expandedSectionBarHeight: CGFloat = 34

    init(store: IslandStateStore, settings: AppSettingsStore) {
        self.init(store: store, settings: settings, initialSection: .calendar)
    }

    fileprivate init(
        store: IslandStateStore,
        settings: AppSettingsStore,
        initialSection: ExpandedSection = .calendar
    ) {
        self.store = store
        self.settings = settings
        _selectedSection = State(initialValue: initialSection)
        _previousSection = State(initialValue: initialSection)
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
        GeometryReader { proxy in
            let islandSize = islandSize(in: proxy.size)

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

                    contentLayer(in: islandSize)
                        .frame(width: islandSize.width, height: islandSize.height, alignment: .top)
                        .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
                }
                .frame(width: islandSize.width, height: islandSize.height)
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
            // The hosting panel can be wider than the collapsed island. This
            // explicit frame preserves the historical behavior where the island
            // stays top-centered inside the panel instead of defaulting to the
            // GeometryReader's top-leading origin.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func islandSize(in panelSize: CGSize) -> CGSize {
        switch store.displayState {
        case .collapsed:
            return CGSize(width: min(IslandLayout.collapsedWidth, panelSize.width), height: IslandLayout.collapsedHeight)
        case .hint:
            let maxHintWidth = max(panelSize.width - IslandLayout.panelHorizontalPadding * 2, IslandLayout.collapsedWidth)
            return CGSize(width: min(CGFloat(settings.expandWidth), maxHintWidth), height: IslandLayout.hintHeight)
        case .expanded:
            return IslandLayout.expandedIslandSize(in: panelSize)
        }
    }

    private func contentLayer(in islandSize: CGSize) -> some View {
        ZStack {
            collapsedContent
                .opacity(store.isExpanded ? 0 : 1)
                .animation(store.animationsEnabled ? .easeOut(duration: store.isExpanded ? 0.10 : 0.20) : nil,
                           value: store.isExpanded)

            expandedContent(in: islandSize)
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

    private func expandedContent(in islandSize: CGSize) -> some View {
        let layout = expandedLayoutMetrics(for: islandSize)

        return expandedMainContent
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(width: islandSize.width, height: islandSize.height, alignment: .top)
            .background(Color.black)
    }

    private var expandedMainContent: some View {
        GeometryReader { proxy in
            let layout = expandedLayoutMetrics(for: proxy.size)
            let contentAreaHeight = max(118, proxy.size.height - expandedSectionBarHeight - layout.sectionSpacing)

            VStack(spacing: layout.sectionSpacing) {
                expandedSectionContent
                    .id(selectedSection)
                    .frame(minHeight: contentAreaHeight, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .transition(sectionContentTransition)

                expandedSectionBar
                    .frame(height: expandedSectionBarHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, expandedLayoutMetrics(for: IslandLayout.expandedIslandSize(in: IslandLayout.panelSize(for: NSScreen.main))).contentHorizontalPadding)
        .padding(.vertical, expandedLayoutMetrics(for: IslandLayout.expandedIslandSize(in: IslandLayout.panelSize(for: NSScreen.main))).contentVerticalPadding)
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
        HStack(spacing: IslandSpacing.medium) {
            ForEach(ExpandedSection.allCases) { section in
                Button {
                    guard selectedSection != section else { return }
                    previousSection = selectedSection
                    withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: IslandSpacing.xSmall) {
                        Image(systemName: section.symbolName)
                            .font(.system(size: 12, weight: .bold))
                        Text(section.title)
                            .font(.system(size: IslandTypography.caption, weight: .medium))
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
        .padding(.horizontal, IslandSpacing.xxSmall)
        .padding(.vertical, IslandSpacing.xxSmall)
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
        let layout = expandedLayoutMetrics(for: IslandLayout.expandedIslandSize(in: IslandLayout.panelSize(for: NSScreen.main)))

        return HStack(spacing: layout.cardInnerSpacing) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.31, green: 0.58, blue: 1.0).opacity(0.18))

                Image(systemName: "icloud.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: layout.cardInnerSpacing) {
                HStack(alignment: .center) {
                    Text("快捷入口")
                        .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 8)

                    Text("iCloud")
                        .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1.0))
                }

                Text("iCloud 云盘")
                    .font(.system(size: IslandTypography.title, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("直接打开云盘，或者在默认位置快速新建文件夹。")
                    .font(.system(size: IslandTypography.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)

                HStack(spacing: IslandSpacing.medium) {
                    shortcutButton(title: "打开云盘", symbolName: "folder") {
                        openICloudDrive()
                    }

                    shortcutButton(title: "新建文件夹", symbolName: "folder.badge.plus") {
                        createFolderInICloudDrive()
                    }
                }
            }
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var statusPanel: some View {
        GeometryReader { proxy in
            let metrics = statusMetrics(for: proxy.size)
            let availableHeight = max(0, proxy.size.height - metrics.verticalInset * 2)

            HStack(alignment: .top, spacing: metrics.cardSpacing) {
                statusPrimaryCard(scale: metrics.scale)
                    .frame(width: metrics.leftWidth, height: availableHeight)

                VStack(alignment: .leading, spacing: IslandSpacing.xSmall * metrics.scale) {
                    HStack(spacing: 5 * metrics.scale) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.72, green: 0.52, blue: 1.0),
                                        Color(red: 0.48, green: 0.40, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("系统状态")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                    }
                    .padding(.leading, 4)
                    .frame(height: metrics.sectionHeaderHeight)

                    HStack(spacing: metrics.cardSpacing) {
                        statusMetricCard(
                            title: "CPU",
                            value: "38%",
                            detail: "2.8 GHz",
                            footer: "",
                            accent: Color(red: 0.56, green: 0.42, blue: 1.0),
                            progress: 0.38,
                            chartPoints: [0.18, 0.36, 0.24, 0.58, 0.42, 0.21, 0.47, 0.32, 0.49, 0.29, 0.18],
                            footerEmphasis: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: "内存",
                            value: "62%",
                            detail: "9.9 GB / 16 GB",
                            footer: "",
                            accent: Color(red: 0.30, green: 0.56, blue: 1.0),
                            progress: 0.62,
                            chartPoints: [0.22, 0.27, 0.31, 0.25, 0.18, 0.21, 0.35, 0.29, 0.23, 0.26, 0.19],
                            footerEmphasis: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: "存储空间",
                            value: "35%",
                            detail: "179 GB / 512 GB",
                            footer: "179 GB / 512 GB",
                            accent: Color(red: 0.34, green: 0.82, blue: 0.74),
                            progress: 0.35,
                            chartPoints: [],
                            footerEmphasis: 0.65,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: "风扇",
                            value: "1200",
                            detail: "运行平稳",
                            footer: "",
                            accent: Color(red: 0.55, green: 0.42, blue: 1.0),
                            progress: 0.31,
                            chartPoints: [],
                            footerEmphasis: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: availableHeight, alignment: .top)

                VStack(spacing: metrics.cardSpacing) {
                    statusNetworkCard(scale: metrics.scale)
                        .frame(height: metrics.rightCardHeight)

                    statusBatteryCard(scale: metrics.scale)
                        .frame(height: metrics.rightCardHeight)
                }
                .frame(width: metrics.rightWidth, height: availableHeight, alignment: .top)
            }
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.vertical, metrics.verticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }

    private func statusPrimaryCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack(spacing: 7 * scale) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.48, blue: 0.98),
                                    Color(red: 0.40, green: 0.28, blue: 0.90)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26 * scale, height: 26 * scale)

                VStack(alignment: .leading, spacing: max(1, scale)) {
                    Text("MacBook Pro")
                        .font(.system(size: 8.5 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(statusOperatingSystem)
                        .font(.system(size: 6.8 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4 * scale)

                Circle()
                    .fill(Color(red: 0.34, green: 0.84, blue: 0.72))
                    .frame(width: 6 * scale, height: 6 * scale)
            }

            VStack(spacing: 0) {
                statusInfoRow(symbol: "cpu", title: statusChipName, value: "\(ProcessInfo.processInfo.processorCount) 核心", scale: scale)
                statusCardDivider
                statusInfoRow(symbol: "memorychip", title: "内存", value: "16 GB", scale: scale)
                statusCardDivider
                statusInfoRow(symbol: "internaldrive", title: "存储", value: "512 GB", scale: scale)
            }

            Spacer(minLength: 0)

            HStack {
                Text("系统报告")
                    .font(.system(size: 7.2 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 4 * scale)
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.2 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 8 * scale)
            .frame(height: 19 * scale)
            .background(Color.white.opacity(0.032))
            .overlay(
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(statusCardBackground(cornerRadius: 13 * scale))
    }

    private func statusMetricCard(
        title: String,
        value: String,
        detail: String,
        footer: String,
        accent: Color,
        progress: CGFloat,
        chartPoints: [CGFloat],
        footerEmphasis: CGFloat?,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 5 * scale) {
                Circle()
                    .fill(accent)
                    .frame(width: 6 * scale, height: 6 * scale)

                Text(title)
                    .font(.system(size: 7.6 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 5 * scale) {
                statusRing(
                    value: value,
                    unit: title == "风扇" ? "RPM" : nil,
                    progress: progress,
                    accent: accent,
                    scale: scale
                )
                .frame(height: 42 * scale)
                .frame(maxWidth: .infinity)

                if title == "存储空间" {
                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text(footer)
                            .font(.system(size: 6.2 * scale, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.70))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        GeometryReader { storageProxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent.opacity(0.95), accent.opacity(0.72)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: storageProxy.size.width * progress)
                            }
                        }
                        .frame(height: 6 * scale)
                    }
                } else if !chartPoints.isEmpty {
                    statusWaveform(points: chartPoints, color: accent, scale: scale)

                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 6.7 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 6.9 * scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 7 * scale)
            .padding(.top, 6 * scale)
            .padding(.bottom, 7 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(statusCardBackground(cornerRadius: 18 * scale))
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusNetworkCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(alignment: .center, spacing: 4 * scale) {
                Image(systemName: "wifi")
                    .font(.system(size: 9.5 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 1.0))

                Text("Wi-Fi")
                    .font(.system(size: 8.5 * scale, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 2 * scale)

                Text("5 GHz")
                    .font(.system(size: 6.8 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6 * scale) {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 6.5 * scale, weight: .bold))
                        Text("32.6")
                            .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                        Text("MB/s")
                            .font(.system(size: 6 * scale, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.58, green: 0.44, blue: 1.0))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 3 * scale) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 6.5 * scale, weight: .bold))
                        Text("12.4")
                            .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                        Text("MB/s")
                            .font(.system(size: 6 * scale, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.34, green: 0.88, blue: 0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)

                VStack(spacing: 4) {
                    statusWaveform(
                        points: [0.34, 0.48, 0.30, 0.52, 0.40, 0.61, 0.28, 0.54, 0.36, 0.46],
                        color: Color(red: 0.56, green: 0.42, blue: 1.0),
                        scale: scale
                    )
                    statusWaveform(
                        points: [0.12, 0.18, 0.10, 0.19, 0.15, 0.23, 0.11, 0.18, 0.12, 0.16],
                        color: Color(red: 0.34, green: 0.88, blue: 0.72),
                        scale: scale
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(statusCardBackground(cornerRadius: 14 * scale))
    }

    private func statusBatteryCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: "battery.100")
                    .font(.system(size: 9.5 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.84, blue: 0.58))

                Text("电池")
                    .font(.system(size: 8.5 * scale, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 2 * scale)

                Text("87%")
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .fixedSize()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.34, green: 0.84, blue: 0.58),
                                    Color(red: 0.36, green: 0.90, blue: 0.74)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.87)
                }
            }
            .frame(height: 8 * scale)

            HStack(spacing: 4 * scale) {
                Text("剩余")
                    .font(.system(size: 6.8 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 2 * scale)

                Text("4 小时 32 分")
                    .font(.system(size: 7.2 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(statusCardBackground(cornerRadius: 14 * scale))
    }

    private func statusInfoRow(symbol: String, title: String, value: String, scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 7.6 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 11 * scale)

            Text(title)
                .font(.system(size: 7 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4 * scale)

            Text(value)
                .font(.system(size: 7.4 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 16 * scale)
    }

    private var statusCardDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
    }

    private func statusWaveform(points: [CGFloat], color: Color, scale: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = max(proxy.size.height, 1)
            let stepX = points.count > 1 ? width / CGFloat(points.count - 1) : 0

            let linePath = Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: 0, y: height - (first * height)))

                for (index, point) in points.enumerated().dropFirst() {
                    path.addLine(to: CGPoint(x: CGFloat(index) * stepX, y: height - (point * height)))
                }
            }

            ZStack {
                linePath
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: 2.5 * scale)

                linePath
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 11 * scale)
    }

    private var statusOperatingSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    private var statusChipName: String {
        ProcessInfo.processInfo.isiOSAppOnMac ? "Apple Silicon" : "Apple M 系列"
    }

    private func statusRing(
        value: String,
        unit: String?,
        progress: CGFloat,
        accent: Color,
        scale: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5.5 * scale)

            Circle()
                .trim(from: 0.06, to: progress * 0.88 + 0.06)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.16), accent.opacity(0.74), accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round)
                )
                .rotationEffect(.degrees(136))

            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 1)
                .blur(radius: 5 * scale)

            VStack(spacing: 3 * scale) {
                Text(value)
                    .font(.system(size: (unit == nil ? 12.5 : 11.5) * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let unit {
                    Text(unit)
                        .font(.system(size: 6.5 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.50))
                }
            }
        }
        .frame(width: 44 * scale, height: 44 * scale)
    }

    private func statusCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.055),
                        Color.white.opacity(0.022)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 0.8)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 18)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
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
        let layout = expandedLayoutMetrics(for: IslandLayout.expandedIslandSize(in: IslandLayout.panelSize(for: NSScreen.main)))

        return HStack(spacing: layout.cardInnerSpacing) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: layout.cardInnerSpacing * 0.8) {
                HStack(alignment: .center) {
                    Text(eyebrow)
                        .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer(minLength: 8)

                    Text(trailing)
                        .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.system(size: IslandTypography.title, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: IslandTypography.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                Text(body)
                    .font(.system(size: IslandTypography.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(layout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func shortcutButton(title: String, symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: IslandSpacing.small) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: IslandTypography.eyebrow, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, IslandSpacing.large)
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
        let layout = expandedLayoutMetrics(for: IslandLayout.expandedIslandSize(in: IslandLayout.panelSize(for: NSScreen.main)))

        return VStack(alignment: .leading, spacing: IslandSpacing.medium) {
            Text(title.uppercased())
                .font(.system(size: IslandTypography.caption, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: emphasis ? IslandTypography.metric : IslandTypography.title, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("通过底部按钮切换容器内容")
                .font(.system(size: IslandTypography.eyebrow, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(layout.cardPadding)
    }

    private var calendarBlock: some View {
        GeometryReader { proxy in
            let metrics = calendarMetrics(for: proxy.size.width)

            HStack(alignment: .top, spacing: 0) {
                calendarSummaryColumn(metrics: metrics)
                    .frame(width: metrics.summaryWidth)

                calendarDivider

                calendarMonthColumn(metrics: metrics)
                    .frame(width: metrics.monthWidth)

                calendarDivider

                calendarAgendaColumn(metrics: metrics)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

    private func calendarSummaryColumn(metrics: CalendarMetrics) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.small) {
            HStack(alignment: .top, spacing: IslandSpacing.small + 1) {
                calendarDateBadge(metrics: metrics)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCalendarDate?.formatted(.dateTime.year()) ?? "日历")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                        .lineLimit(1)

                    Text(selectedCalendarDate.map(fullWeekdayLabel(for:)) ?? "系统日历")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    calendarWeatherPill(metrics: metrics)
                }
            }

            calendarFeaturedEventCard(metrics: metrics)
        }
        .padding(.trailing, IslandSpacing.small + 1)
        .padding(.top, IslandSpacing.xSmall)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func calendarDateBadge(metrics: CalendarMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.badgeSize * 0.48, style: .continuous)
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
                    RoundedRectangle(cornerRadius: metrics.badgeSize * 0.48, style: .continuous)
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
        .frame(width: metrics.badgeSize, height: metrics.badgeSize)
    }

    private func calendarWeatherPill(metrics: CalendarMetrics) -> some View {
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
        .padding(.horizontal, IslandSpacing.medium)
        .frame(minHeight: metrics.pillHeight)
        .background(Color.white.opacity(0.05))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .clipShape(Capsule())
    }

    private func calendarFeaturedEventCard(metrics: CalendarMetrics) -> some View {
        let detail = selectedCalendarEntry?.detail ?? placeholderDetail
        let accent = accentColor(for: selectedCalendarEntry)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: IslandSpacing.xSmall + 1) {
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
                    .frame(minHeight: metrics.badgeHeight)
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
        .padding(IslandSpacing.small)
        .frame(minHeight: metrics.featuredCardMinHeight, alignment: .topLeading)
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

    private func calendarMonthColumn(metrics: CalendarMetrics) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xSmall) {
            HStack(spacing: IslandSpacing.xSmall) {
                monthNavigationButton(systemName: "chevron.left", metrics: metrics) {
                    shiftPresentedMonth(by: -1)
                }

                Text(presentedMonthAnchor.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .frame(maxWidth: .infinity, alignment: .center)

                monthNavigationButton(systemName: "chevron.right", metrics: metrics) {
                    shiftPresentedMonth(by: 1)
                }
            }

            calendarWeekHeader

            calendarMonthGrid(metrics: metrics)
        }
        .padding(.horizontal, IslandSpacing.small + 1)
        .padding(.top, IslandSpacing.xSmall)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func monthNavigationButton(systemName: String, metrics: CalendarMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: metrics.navButtonSize, height: metrics.navButtonSize)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: metrics.navButtonSize / 2, style: .continuous))
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

    private func calendarMonthGrid(metrics: CalendarMetrics) -> some View {
        let days = monthGridDays

        return VStack(spacing: 1) {
            ForEach(0..<days.count / 7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        calendarMonthDayCell(day, metrics: metrics)
                    }
                }
            }
        }
    }

    private func calendarMonthDayCell(_ date: Date, metrics: CalendarMetrics) -> some View {
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
                    .frame(width: metrics.calendarCellSize, height: metrics.calendarCellSize)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: metrics.calendarCellSize * 0.66, style: .continuous)
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
                        .frame(width: metrics.dotSize, height: metrics.dotSize)
                        .offset(y: 1)
                } else if isToday {
                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: metrics.dotSize, height: metrics.dotSize)
                        .offset(y: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.calendarCellSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry == nil)
    }

    private func calendarAgendaColumn(metrics: CalendarMetrics) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.small) {
            HStack {
                Text("今日安排")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text("\(agendaEntries.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.70, green: 0.60, blue: 1.0))
                    .padding(.horizontal, 6)
                    .frame(minHeight: metrics.badgeHeight)
                    .background(Color(red: 0.42, green: 0.38, blue: 0.92).opacity(0.14))
                    .clipShape(Capsule())

                Spacer(minLength: IslandSpacing.medium)

                Button {
                    jumpToTodayCalendarEntry()
                } label: {
                    HStack(spacing: IslandSpacing.small) {
                        Text("今天")
                        Image(systemName: "calendar")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, IslandSpacing.small + 1)
                    .frame(minHeight: metrics.badgeHeight + 2)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(IslandShortcutButtonStyle())
            }

            VStack(spacing: IslandSpacing.xSmall + 1) {
                ForEach(displayedAgendaEntries) { entry in
                    agendaEventCard(entry, metrics: metrics)
                }
            }
        }
        .padding(.leading, IslandSpacing.medium + 1)
        .padding(.top, IslandSpacing.xxSmall)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agendaEventCard(_ entry: IslandContent.CalendarDayEntry, metrics: CalendarMetrics) -> some View {
        let detail = entry.detail
        let accent = accentColor(for: entry)
        let isSelected = entry.id == selectedCalendarEntry?.id

        return Button {
            withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
                selectedCalendarEntryID = entry.id
            }
        } label: {
            HStack(spacing: IslandSpacing.medium) {
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

                Spacer(minLength: IslandSpacing.small)

                Text(calendarStatusBadgeText(for: entry))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.62))
                    .padding(.horizontal, 6)
                    .frame(minHeight: metrics.badgeHeight)
                    .background((isSelected ? accent.opacity(0.16) : Color.white.opacity(0.05)))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, IslandSpacing.small + 1)
            .padding(.vertical, IslandSpacing.xSmall)
            .frame(minHeight: metrics.agendaCardMinHeight)
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

    private func statusMetrics(for availableSize: CGSize) -> StatusMetrics {
        let scale = IslandLayout.clamp(
            min(availableSize.width / IslandLayout.expandedIdealWidth, availableSize.height / 130),
            min: 0.88,
            max: 1.14
        )
        let cardSpacing = 8 * scale
        let horizontalInset = 6 * scale
        let verticalInset = 4 * scale
        let availableWidth = max(0, availableSize.width - horizontalInset * 2)
        let availableHeight = max(0, availableSize.height - verticalInset * 2)
        let leftWidth = IslandLayout.clamp(availableWidth * 0.26, min: 134 * scale, max: 152 * scale)
        let rightWidth = IslandLayout.clamp(availableWidth * 0.218, min: 112 * scale, max: 132 * scale)
        let centerWidth = max(0, availableWidth - leftWidth - rightWidth - (cardSpacing * 2))
        let metricWidth = max(50 * scale, (centerWidth - (cardSpacing * 3)) / 4)
        let rightCardHeight = IslandLayout.clamp((availableHeight - cardSpacing) / 2, min: 42 * scale, max: 56 * scale)
        let metricCardHeight = IslandLayout.clamp(availableHeight - (22 * scale), min: 72 * scale, max: 92 * scale)

        return StatusMetrics(
            scale: scale,
            cardSpacing: cardSpacing,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            leftWidth: leftWidth,
            rightWidth: rightWidth,
            metricWidth: metricWidth,
            rightCardHeight: rightCardHeight,
            metricCardHeight: metricCardHeight,
            sectionHeaderHeight: 16 * scale
        )
    }

    private func calendarMetrics(for availableWidth: CGFloat) -> CalendarMetrics {
        let scale = IslandLayout.clamp(availableWidth / IslandLayout.expandedIdealWidth, min: 0.92, max: 1.08)
        let summaryWidth = IslandLayout.clamp(availableWidth * 0.26, min: 140, max: 170)
        let monthWidth = IslandLayout.clamp(availableWidth * 0.32, min: 176, max: 210)

        return CalendarMetrics(
            scale: scale,
            summaryWidth: summaryWidth,
            monthWidth: monthWidth,
            badgeSize: IslandLayout.clamp(42 * scale, min: 38, max: 46),
            pillHeight: IslandLayout.clamp(18 * scale, min: 16, max: 20),
            navButtonSize: IslandLayout.clamp(18 * scale, min: 18, max: 22),
            featuredCardMinHeight: IslandLayout.clamp(50 * scale, min: 46, max: 58),
            agendaCardMinHeight: IslandLayout.clamp(42 * scale, min: 38, max: 50),
            calendarCellSize: IslandLayout.clamp(monthWidth / 12, min: 14, max: 17),
            dotSize: IslandLayout.clamp(1.5 * scale, min: 1.5, max: 2.2),
            badgeHeight: IslandLayout.clamp(18 * scale, min: 16, max: 20)
        )
    }

    private func expandedLayoutMetrics(for availableSize: CGSize) -> ExpandedLayoutMetrics {
        let scale = IslandLayout.clamp(
            min(availableSize.width / IslandLayout.expandedIdealWidth, availableSize.height / IslandLayout.expandedMinHeight),
            min: 0.9,
            max: 1.08
        )

        return ExpandedLayoutMetrics(
            horizontalPadding: 18 * scale,
            topPadding: 42 * scale,
            bottomPadding: 30 * scale,
            sectionSpacing: 10 * scale,
            contentHorizontalPadding: 8 * scale,
            contentVerticalPadding: 6 * scale,
            cardPadding: 14 * scale,
            cardInnerSpacing: 10 * scale
        )
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
    }(), settings: AppSettingsStore(), initialSection: .status)
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
