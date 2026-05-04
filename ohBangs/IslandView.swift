import SwiftUI
import AppKit
import CoreLocation

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

private enum WeatherSymbolKind {
    case sunny
    case sunCloud
    case rainy
    case storm
    case cloudy
    case moon
    case snow
    case generic

    init(symbolName: String) {
        if symbolName.contains("bolt") {
            self = .storm
        } else if symbolName.contains("rain") || symbolName.contains("drizzle") || symbolName.contains("heavyrain") {
            self = .rainy
        } else if symbolName.contains("snow") || symbolName.contains("sleet") {
            self = .snow
        } else if symbolName.contains("moon") {
            self = .moon
        } else if symbolName.contains("cloud") && symbolName.contains("sun") {
            self = .sunCloud
        } else if symbolName.contains("sun") {
            self = .sunny
        } else if symbolName.contains("cloud") || symbolName.contains("fog") {
            self = .cloudy
        } else {
            self = .generic
        }
    }
}

private struct WeatherAnimatedSymbol: View {
    let symbolName: String
    let size: CGFloat
    let gradient: LinearGradient
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let isAnimated: Bool

    private var kind: WeatherSymbolKind { WeatherSymbolKind(symbolName: symbolName) }

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { context in
                    symbolBody(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                symbolBody(at: 0)
            }
        }
        .frame(width: size * 1.25, height: size * 1.25)
    }

    @ViewBuilder
    private func symbolBody(at time: TimeInterval) -> some View {
        let floatOffset = isAnimated ? CGFloat(sin(time * 1.35)) * size * 0.04 : 0
        let breathScale = isAnimated ? 1 + CGFloat(sin(time * 1.15)) * 0.025 : 1

        ZStack {
            switch kind {
            case .sunny:
                sunnyBody(at: time)
            case .sunCloud:
                sunCloudBody(at: time)
            case .rainy:
                rainyBody(at: time, includesBolt: false)
            case .storm:
                rainyBody(at: time, includesBolt: true)
            case .cloudy:
                cloudBody(at: time)
            case .moon:
                moonBody(at: time)
            case .snow:
                snowBody(at: time)
            case .generic:
                fallbackBody
            }
        }
        .scaleEffect(breathScale)
        .offset(y: floatOffset)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }

    private var fallbackBody: some View {
        Image(systemName: symbolName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(gradient)
    }

    private func sunnyBody(at time: TimeInterval) -> some View {
        let rotation = Angle.degrees(isAnimated ? (time * 22).truncatingRemainder(dividingBy: 360) : 0)

        return ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.83, blue: 0.35).opacity(0.98),
                                Color(red: 1.0, green: 0.92, blue: 0.68).opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.1, height: size * 0.36)
                    .offset(y: -size * 0.31)
                    .rotationEffect(.degrees(Double(index) * 45) + rotation)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.94, blue: 0.72),
                            Color(red: 1.0, green: 0.78, blue: 0.25)
                        ],
                        center: .center,
                        startRadius: size * 0.03,
                        endRadius: size * 0.34
                    )
                )
                .frame(width: size * 0.56, height: size * 0.56)
        }
    }

    private func sunCloudBody(at time: TimeInterval) -> some View {
        let drift = isAnimated ? CGFloat(sin(time * 0.85)) * size * 0.05 : 0
        let frontDrift = isAnimated ? CGFloat(sin((time * 1.05) + 0.8)) * size * 0.03 : 0

        return ZStack {
            sunnyBody(at: time)
                .scaleEffect(0.78)
                .offset(x: -size * 0.16, y: -size * 0.12)

            layeredCloud(scale: 0.78, opacity: 0.42)
                .offset(x: -size * 0.04 + drift, y: size * 0.08)

            layeredCloud(scale: 0.9, opacity: 1)
                .offset(x: size * 0.08 + frontDrift, y: size * 0.15)
        }
    }

    private func rainyBody(at time: TimeInterval, includesBolt: Bool) -> some View {
        ZStack {
            layeredCloud(scale: 0.92, opacity: 0.9)
                .offset(y: -size * 0.02)

            layeredCloud(scale: 0.72, opacity: 0.34)
                .offset(x: -size * 0.14, y: -size * 0.12)

            if includesBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    .offset(x: size * 0.06, y: size * 0.18)
            }

            ForEach(0..<3, id: \.self) { index in
                let progress = isAnimated
                    ? ((time * 1.7) + (Double(index) * 0.24)).truncatingRemainder(dividingBy: 1)
                    : (0.24 * Double(index))
                let yOffset = (CGFloat(progress) * size * 0.34) - size * 0.02
                let opacity = 0.25 + ((1 - progress) * 0.7)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.86, blue: 1.0).opacity(opacity),
                                Color.white.opacity(opacity * 0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.08, height: size * 0.24)
                    .offset(
                        x: (-size * 0.16) + (CGFloat(index) * size * 0.16),
                        y: size * 0.16 + yOffset
                    )
            }
        }
    }

    private func cloudBody(at time: TimeInterval) -> some View {
        let backDrift = isAnimated ? CGFloat(sin(time * 0.72)) * size * 0.05 : 0
        let frontDrift = isAnimated ? CGFloat(sin((time * 0.98) + 1.3)) * size * 0.035 : 0

        return ZStack {
            layeredCloud(scale: 0.76, opacity: 0.36)
                .offset(x: -size * 0.08 + backDrift, y: -size * 0.06)

            layeredCloud(scale: 0.98, opacity: 1)
                .offset(x: size * 0.04 + frontDrift, y: size * 0.08)
        }
    }

    private func moonBody(at time: TimeInterval) -> some View {
        let starOpacity = isAnimated ? 0.45 + (CGFloat(sin(time * 2.1)) * 0.3) : 0.55

        return ZStack {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: size * 0.92, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.76, green: 0.83, blue: 1.0),
                            Color(red: 0.55, green: 0.63, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(starOpacity))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.24, y: -size * 0.18)
        }
    }

    private func snowBody(at time: TimeInterval) -> some View {
        let drift = isAnimated ? CGFloat(sin(time * 1.1)) * size * 0.04 : 0

        return ZStack {
            layeredCloud(scale: 0.9, opacity: 0.96)
                .offset(y: -size * 0.04)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size * 0.08, height: size * 0.08)
                    .offset(
                        x: (-size * 0.14) + (CGFloat(index) * size * 0.14) + drift * (index == 1 ? -0.5 : 0.5),
                        y: size * 0.2 + (CGFloat(index % 2) * size * 0.04)
                    )
            }
        }
    }

    private func layeredCloud(scale: CGFloat, opacity: CGFloat) -> some View {
        Image(systemName: "cloud.fill")
            .font(.system(size: size * scale, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96 * opacity),
                        Color(red: 0.76, green: 0.84, blue: 1.0).opacity(0.86 * opacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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

    private struct AppShortcut: Identifiable {
        let id: String
        let title: String
        let symbolName: String
        let bundleIdentifier: String?
        let appPath: String?
        let tint: Color
    }

    private struct ShortcutPanelMetrics {
        let columnCount: Int
        let gridSpacing: CGFloat
        let sectionSpacing: CGFloat
        let headerBottomSpacing: CGFloat
        let headerHeight: CGFloat
        let cardHeight: CGFloat
        let cardContentSpacing: CGFloat
        let iconContainerSize: CGFloat
        let iconSize: CGFloat
        let titleSize: CGFloat
        let cardCornerRadius: CGFloat
        let dockHeight: CGFloat
        let dockHorizontalPadding: CGFloat
        let dockIconSize: CGFloat
        let activeDockWidth: CGFloat
        let activeDockHeight: CGFloat
    }

    private struct OverviewDashboardMetrics {
        let scale: CGFloat
        let outerInset: CGFloat
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let weatherCardHeight: CGFloat
        let footerCardHeight: CGFloat
        let topRowWidths: [CGFloat]
        let bottomRowWidths: [CGFloat]
        let cardCornerRadius: CGFloat
        let cardHorizontalPadding: CGFloat
        let cardVerticalPadding: CGFloat
        let headerSpacing: CGFloat
        let titleSize: CGFloat
        let accessorySize: CGFloat
        let quickActionCount: Int
        let compactActionSize: CGFloat
    }

    private struct OverviewRecentFile: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let url: URL?
    }

    private struct WeatherPanelMetrics {
        let scale: CGFloat
        let spacing: CGFloat
        let cardHeight: CGFloat
        let currentMinWidth: CGFloat
        let currentIdealWidth: CGFloat
        let hourlyMinWidth: CGFloat
        let hourlyIdealWidth: CGFloat
        let dailyMinWidth: CGFloat
        let dailyIdealWidth: CGFloat
        let iconOrbSize: CGFloat
        let currentTemperatureSize: CGFloat
        let currentConditionSize: CGFloat
        let currentMetaSize: CGFloat
        let supportingTextSize: CGFloat
        let headerTextSize: CGFloat
        let hourlyIconSize: CGFloat
        let hourlyTimeSize: CGFloat
        let hourlyTemperatureSize: CGFloat
        let dayRowHeight: CGFloat
        let dayTextSize: CGFloat
        let dailyHeaderBottomSpacing: CGFloat
        let cardPaddingHorizontal: CGFloat
        let cardPaddingVertical: CGFloat
        let cardCornerRadius: CGFloat
    }

    fileprivate enum ExpandedSection: String, CaseIterable, Identifiable {
        case overview
        case calendar
        case status
        case notification
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "日历"
            case .status: return "状态"
            case .notification: return "天气"
            case .overview: return "首页"
            case .settings: return "设置"
            }
        }

        var symbolName: String {
            switch self {
            case .calendar: return "calendar"
            case .status: return "waveform.path.ecg"
            case .notification: return "cloud.sun"
            case .overview: return "house"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @ObservedObject var store: IslandStateStore
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var weatherStore: WeatherStore
    @Namespace private var sectionBarNamespace
    @State private var selectedSection: ExpandedSection
    @State private var previousSection: ExpandedSection
    @State private var presentedMonthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedCalendarEntryID: String?
    @State private var hoveredEntryID: String?
    @State private var hoveringCalendar: Bool = false
    @State private var hoveredShortcutID: String?

    private static let islandSpring: Animation =
        .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
    private static let sectionSwitchAnimation: Animation =
        .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)

    private static let availableAppShortcuts: [AppShortcut] = [
        AppShortcut(
            id: "calendar",
            title: "日历",
            symbolName: "calendar",
            bundleIdentifier: "com.apple.iCal",
            appPath: nil,
            tint: Color(red: 1.0, green: 0.36, blue: 0.32)
        ),
        AppShortcut(
            id: "files",
            title: "文件",
            symbolName: "folder.fill",
            bundleIdentifier: "com.apple.finder",
            appPath: nil,
            tint: Color(red: 0.32, green: 0.70, blue: 1.0)
        ),
        AppShortcut(
            id: "music",
            title: "音乐",
            symbolName: "music.note",
            bundleIdentifier: "com.apple.Music",
            appPath: nil,
            tint: Color(red: 1.0, green: 0.27, blue: 0.38)
        ),
        AppShortcut(
            id: "notes",
            title: "便签",
            symbolName: "note.text",
            bundleIdentifier: "com.apple.Notes",
            appPath: nil,
            tint: Color(red: 1.0, green: 0.80, blue: 0.23)
        ),
        AppShortcut(
            id: "weather",
            title: "天气",
            symbolName: "cloud.sun.fill",
            bundleIdentifier: "com.apple.weather",
            appPath: nil,
            tint: Color(red: 0.39, green: 0.67, blue: 1.0)
        ),
        AppShortcut(
            id: "safari",
            title: "浏览器",
            symbolName: "safari.fill",
            bundleIdentifier: "com.apple.Safari",
            appPath: nil,
            tint: Color(red: 0.35, green: 0.73, blue: 1.0)
        ),
        AppShortcut(
            id: "terminal",
            title: "终端",
            symbolName: "terminal",
            bundleIdentifier: "com.apple.Terminal",
            appPath: nil,
            tint: Color.white.opacity(0.86)
        ),
        AppShortcut(
            id: "settings",
            title: "设置",
            symbolName: "gearshape.fill",
            bundleIdentifier: "com.apple.systempreferences",
            appPath: nil,
            tint: Color.white.opacity(0.72)
        )
    ]

    private let expandedSectionBarHeight: CGFloat = 34

    init(store: IslandStateStore, settings: AppSettingsStore, weatherStore: WeatherStore) {
        self.init(store: store, settings: settings, weatherStore: weatherStore, initialSection: .overview)
    }

    fileprivate init(
        store: IslandStateStore,
        settings: AppSettingsStore,
        weatherStore: WeatherStore,
        initialSection: ExpandedSection = .calendar
    ) {
        self.store = store
        self.settings = settings
        self.weatherStore = weatherStore
        _selectedSection = State(initialValue: initialSection)
        _previousSection = State(initialValue: initialSection)
    }

    private func activateSection(_ section: ExpandedSection) {
        guard selectedSection != section else {
            store.expand()
            return
        }

        previousSection = selectedSection
        withAnimation(store.animationsEnabled ? Self.sectionSwitchAnimation : nil) {
            selectedSection = section
        }
        store.expand()
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

    private var appShortcuts: [AppShortcut] {
        let builtInShortcuts = Dictionary(uniqueKeysWithValues: Self.availableAppShortcuts.map { ($0.id, $0) })
        let customShortcuts = Dictionary(uniqueKeysWithValues: settings.customShortcutOptions.map { option in
            (
                option.id,
                AppShortcut(
                    id: option.id,
                    title: option.title,
                    symbolName: option.symbolName,
                    bundleIdentifier: option.bundleIdentifier,
                    appPath: option.appPath,
                    tint: Color.white.opacity(0.82)
                )
            )
        })

        return settings.pinnedShortcutIDs.compactMap { id in
            builtInShortcuts[id] ?? customShortcuts[id]
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
                        activateSection(.settings)
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
            .overlay(alignment: .topLeading) {
                if selectedSection == .overview {
                    overviewFloatingHeader
                        .padding(.leading, layout.horizontalPadding + layout.contentHorizontalPadding)
                        .padding(.trailing, layout.horizontalPadding + layout.contentHorizontalPadding)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
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
        HStack(spacing: 10) {
            ForEach(ExpandedSection.allCases) { section in
                Button {
                    activateSection(section)
                } label: {
                    ZStack {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.33, green: 0.28, blue: 0.72).opacity(0.92),
                                            Color(red: 0.44, green: 0.33, blue: 0.98).opacity(0.78)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .shadow(color: Color(red: 0.40, green: 0.30, blue: 0.95).opacity(0.28), radius: 12, y: 4)
                                .matchedGeometryEffect(id: "selectedSectionBackground", in: sectionBarNamespace)
                        }

                        Image(systemName: section.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: expandedSectionBarHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(IslandSegmentButtonStyle(isSelected: selectedSection == section))
                .help(section.title)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.022), Color.white.opacity(0.008)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
        )
    }

    private var statusPanel: some View {
        GeometryReader { proxy in
            let metrics = statusMetrics(for: proxy.size)
            let availableHeight = max(0, proxy.size.height - metrics.verticalInset * 2)
            let status = store.currentContent.systemStatus ?? unavailableSystemStatus

            HStack(alignment: .top, spacing: metrics.cardSpacing) {
                statusPrimaryCard(status.primary, scale: metrics.scale)
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
                            title: status.cpu.title,
                            value: status.cpu.valueText,
                            detail: status.cpu.detailText,
                            footer: status.cpu.footerText,
                            accent: Color(red: 0.56, green: 0.42, blue: 1.0),
                            progress: status.cpu.progress,
                            chartPoints: normalizedHistoryPoints(status.cpu.history),
                            footerEmphasis: nil,
                            unit: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: status.memory.title,
                            value: status.memory.valueText,
                            detail: status.memory.detailText,
                            footer: status.memory.footerText,
                            accent: Color(red: 0.30, green: 0.56, blue: 1.0),
                            progress: status.memory.progress,
                            chartPoints: normalizedHistoryPoints(status.memory.history),
                            footerEmphasis: nil,
                            unit: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: status.storage.title,
                            value: status.storage.valueText,
                            detail: status.storage.detailText,
                            footer: status.storage.footerText,
                            accent: Color(red: 0.34, green: 0.82, blue: 0.74),
                            progress: status.storage.progress,
                            chartPoints: normalizedHistoryPoints(status.storage.history),
                            footerEmphasis: 0.65,
                            unit: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)

                        statusMetricCard(
                            title: status.thermal.title,
                            value: status.thermal.valueText,
                            detail: status.thermal.detailText,
                            footer: status.thermal.footerText,
                            accent: Color(red: 0.55, green: 0.42, blue: 1.0),
                            progress: status.thermal.progress,
                            chartPoints: normalizedHistoryPoints(status.thermal.history),
                            footerEmphasis: nil,
                            unit: nil,
                            scale: metrics.scale
                        )
                        .frame(width: metrics.metricWidth, height: metrics.metricCardHeight)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: availableHeight, alignment: .top)

                VStack(spacing: metrics.cardSpacing) {
                    statusNetworkCard(status.network, scale: metrics.scale)
                        .frame(height: metrics.rightCardHeight)

                    statusBatteryCard(status.battery, scale: metrics.scale)
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

    private func statusPrimaryCard(_ primary: IslandContent.SystemStatus.Primary, scale: CGFloat) -> some View {
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
                    Text(primary.machineName)
                        .font(.system(size: 8.5 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(primary.operatingSystem)
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
                statusInfoRow(symbol: "cpu", title: primary.chipName, value: "\(ProcessInfo.processInfo.processorCount) 核心", scale: scale)
                statusCardDivider
                statusInfoRow(symbol: "memorychip", title: "内存", value: primary.memoryCapacityText, scale: scale)
                statusCardDivider
                statusInfoRow(symbol: "internaldrive", title: "存储", value: primary.storageCapacityText, scale: scale)
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
        unit: String?,
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
                    unit: unit,
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

    private func statusNetworkCard(_ network: IslandContent.SystemStatus.Network, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(alignment: .center, spacing: 4 * scale) {
                Image(systemName: "wifi")
                    .font(.system(size: 9.5 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 1.0))

                Text(network.networkName)
                    .font(.system(size: 8.5 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2 * scale)

                Text(network.bandText)
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
                        Text(dataRateText(network.uploadRateBytesPerSecond))
                            .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.58, green: 0.44, blue: 1.0))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 3 * scale) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 6.5 * scale, weight: .bold))
                        Text(dataRateText(network.downloadRateBytesPerSecond))
                            .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.34, green: 0.88, blue: 0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)

                VStack(spacing: 4) {
                    statusWaveform(
                        points: normalizedHistoryPoints(network.uploadHistory),
                        color: Color(red: 0.56, green: 0.42, blue: 1.0),
                        scale: scale
                    )
                    statusWaveform(
                        points: normalizedHistoryPoints(network.downloadHistory),
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

    private func statusBatteryCard(_ battery: IslandContent.SystemStatus.Battery, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(spacing: 4 * scale) {
                Image(systemName: batterySymbolName(for: battery))
                    .font(.system(size: 9.5 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.84, blue: 0.58))

                Text("电池")
                    .font(.system(size: 8.5 * scale, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 2 * scale)

                Text(battery.levelText)
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
                        .frame(width: proxy.size.width * CGFloat((battery.levelPercent ?? 0) / 100))
                }
            }
            .frame(height: 8 * scale)

            HStack(spacing: 4 * scale) {
                Text(battery.statusText)
                    .font(.system(size: 6.8 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 2 * scale)

                Text(battery.timeRemainingText)
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

    private var unavailableSystemStatus: IslandContent.SystemStatus {
        .init(
            primary: .init(
                machineName: Host.current().localizedName ?? "Mac",
                operatingSystem: "正在读取系统状态",
                chipName: "等待系统数据",
                memoryCapacityText: "--",
                storageCapacityText: "--"
            ),
            cpu: .init(title: "CPU", valueText: "--", detailText: "等待数据", footerText: "", progress: 0, history: []),
            memory: .init(title: "内存", valueText: "--", detailText: "等待数据", footerText: "", progress: 0, history: []),
            storage: .init(title: "存储空间", valueText: "--", detailText: "等待数据", footerText: "", progress: 0, history: []),
            thermal: .init(title: "热压", valueText: "--", detailText: "等待数据", footerText: "", progress: 0, history: []),
            network: .init(networkName: "未读取", bandText: "--", uploadRateBytesPerSecond: 0, downloadRateBytesPerSecond: 0, uploadHistory: [], downloadHistory: []),
            battery: .init(levelPercent: nil, levelText: "--", statusText: "等待数据", timeRemainingText: "--", isCharging: false)
        )
    }

    private var displayedWeatherSnapshot: WeatherSnapshot {
        weatherStore.snapshot ?? .placeholder
    }

    private func normalizedHistoryPoints(_ history: [Double]) -> [CGFloat] {
        let sanitized = history.map { max($0, 0) }
        guard let maxValue = sanitized.max(), maxValue > 0 else {
            return sanitized.map { _ in 0.12 }
        }
        return sanitized.map { CGFloat($0 / maxValue) }
    }

    private func dataRateText(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.2f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.2f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.2f B/s", bytesPerSecond)
        }
    }

    private func batterySymbolName(for battery: IslandContent.SystemStatus.Battery) -> String {
        if battery.isCharging {
            return "battery.100.bolt"
        }

        guard let level = battery.levelPercent else { return "powerplug" }
        switch level {
        case ..<20:
            return "battery.25"
        case ..<50:
            return "battery.50"
        case ..<80:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    private var notificationPanel: some View {
        return GeometryReader { proxy in
            let layout = expandedLayoutMetrics(for: proxy.size)
            let metrics = weatherPanelMetrics(for: proxy.size)

            Group {
                if let weather = weatherStore.snapshot {
                    HStack(spacing: metrics.spacing) {
                        weatherCurrentColumn(weather, metrics: metrics)
                            .frame(minWidth: metrics.currentMinWidth, idealWidth: metrics.currentIdealWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .layoutPriority(4)

                        weatherHourlyCard(weather, metrics: metrics)
                            .frame(minWidth: metrics.hourlyMinWidth, idealWidth: metrics.hourlyIdealWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .layoutPriority(3)

                        weatherDailyCard(weather, metrics: metrics)
                            .frame(minWidth: metrics.dailyMinWidth, idealWidth: metrics.dailyIdealWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .layoutPriority(3)
                    }
                } else if weatherStore.isLoading {
                    weatherLoadingPanel(metrics: metrics)
                } else if let errorMessage = weatherStore.errorMessage {
                    weatherUnavailablePanel(message: errorMessage, metrics: metrics)
                } else {
                    weatherUnavailablePanel(message: "请允许定位或点按重试", metrics: metrics)
                }
            }
            .frame(height: metrics.cardHeight, alignment: .top)
            .padding(.horizontal, layout.cardPadding * 0.8)
            .padding(.top, 0)
            .padding(.bottom, 3 * metrics.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func weatherUnavailablePanel(message: String, metrics: WeatherPanelMetrics) -> some View {
        HStack(spacing: 14 * metrics.scale) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.09),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                Image(systemName: weatherStore.authorizationStatus == .denied || weatherStore.authorizationStatus == .restricted ? "location.slash.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: metrics.iconOrbSize * 0.34, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .frame(width: metrics.iconOrbSize * 0.84, height: metrics.iconOrbSize * 0.84)

            VStack(alignment: .leading, spacing: 8 * metrics.scale) {
                Text(weatherStore.authorizationStatus == .denied || weatherStore.authorizationStatus == .restricted ? "无法获取位置" : "天气暂时不可用")
                    .font(.system(size: metrics.currentConditionSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(weatherStore.authorizationStatus == .denied || weatherStore.authorizationStatus == .restricted
                    ? "请在系统设置的定位服务中允许 ohBangs 访问你的位置。"
                    : message
                )
                .font(.system(size: metrics.currentMetaSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)

                Button {
                    weatherStore.refresh()
                } label: {
                    Text(weatherStore.authorizationStatus == .denied || weatherStore.authorizationStatus == .restricted ? "重新检查权限" : "重试")
                        .font(.system(size: metrics.supportingTextSize * 1.1, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12 * metrics.scale)
                        .padding(.vertical, 6 * metrics.scale)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.cardPaddingHorizontal)
        .padding(.vertical, metrics.cardPaddingVertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(weatherCardBackground(cornerRadius: metrics.cardCornerRadius))
    }

    private func weatherLoadingPanel(metrics: WeatherPanelMetrics) -> some View {
        HStack(spacing: 14 * metrics.scale) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)

            VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                Text("正在获取天气")
                    .font(.system(size: metrics.currentConditionSize, weight: .bold))
                    .foregroundStyle(.white)

                Text("等待定位与天气数据返回")
                    .font(.system(size: metrics.currentMetaSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.cardPaddingHorizontal)
        .padding(.vertical, metrics.cardPaddingVertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(weatherCardBackground(cornerRadius: metrics.cardCornerRadius))
    }

    private var overviewPanel: some View {
        GeometryReader { proxy in
            let metrics = overviewDashboardMetrics(for: proxy.size)

            VStack(alignment: .leading, spacing: metrics.verticalSpacing) {
                HStack(alignment: .top, spacing: metrics.horizontalSpacing) {
                    overviewWeatherCard(height: metrics.weatherCardHeight, metrics: metrics)
                        .frame(width: metrics.topRowWidths[0], alignment: .leading)

                    overviewRecentFilesCard(height: metrics.weatherCardHeight, metrics: metrics)
                        .frame(width: metrics.topRowWidths[1], alignment: .leading)

                    overviewSystemStatusCard(height: metrics.weatherCardHeight, metrics: metrics)
                        .frame(width: metrics.topRowWidths[2], alignment: .leading)
                }

                HStack(alignment: .top, spacing: metrics.horizontalSpacing) {
                    overviewAgendaCard(height: metrics.footerCardHeight, metrics: metrics)
                        .frame(width: metrics.bottomRowWidths[0], alignment: .leading)

                    overviewNotificationCard(height: metrics.footerCardHeight, metrics: metrics)
                        .frame(width: metrics.bottomRowWidths[1], alignment: .leading)

                    overviewQuickActionsCard(height: metrics.footerCardHeight, metrics: metrics)
                        .frame(width: metrics.bottomRowWidths[2], alignment: .leading)
                }
            }
            .padding(.horizontal, metrics.outerInset)
            .padding(.bottom, max(2, 3 * metrics.scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var overviewFloatingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("首页")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Text("常用功能总览")
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text("今日概览")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Circle()
                    .fill(Color(red: 0.44, green: 0.35, blue: 1.0))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overviewDashboardMetrics(for size: CGSize) -> OverviewDashboardMetrics {
        let compactHeight = size.height < 170
        let compactWidth = size.width < 560
        let outerInset: CGFloat = compactWidth ? 8 : 10
        let referenceWidth: CGFloat = compactWidth ? 512 : 706
        let topReferenceHeight: CGFloat = compactWidth ? 64 : 76
        let bottomReferenceHeight: CGFloat = compactWidth ? 52 : 58
        let referenceSpacing: CGFloat = compactHeight ? 6 : 8
        let referenceHeight = topReferenceHeight + referenceSpacing + bottomReferenceHeight
        let availableWidth = max(280, size.width - (outerInset * 2))
        let availableHeight = max(96, size.height)
        let widthScale = availableWidth / referenceWidth
        let heightScale = availableHeight / referenceHeight
        let scale = min(widthScale, heightScale)
        let horizontalSpacing = max(6, round((compactWidth ? 7 : 8) * scale))
        let verticalSpacing = max(6, round(referenceSpacing * scale))
        let weatherCardHeight = max(58, round(topReferenceHeight * scale))
        let footerCardHeight = max(46, round(bottomReferenceHeight * scale))
        let topReferenceWidths: [CGFloat] = compactWidth ? [170, 202, 140] : [170, 320, 220]
        let bottomReferenceWidths: [CGFloat] = compactWidth ? [164, 162, 170] : [222, 244, 224]
        let topRowWidths = overviewScaledWidths(
            availableWidth: availableWidth,
            referenceWidths: topReferenceWidths,
            spacing: horizontalSpacing
        )
        let bottomRowWidths = overviewScaledWidths(
            availableWidth: availableWidth,
            referenceWidths: bottomReferenceWidths,
            spacing: horizontalSpacing
        )

        return OverviewDashboardMetrics(
            scale: scale,
            outerInset: outerInset,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            weatherCardHeight: weatherCardHeight,
            footerCardHeight: footerCardHeight,
            topRowWidths: topRowWidths,
            bottomRowWidths: bottomRowWidths,
            cardCornerRadius: max(18, round(20 * scale)),
            cardHorizontalPadding: max(9, round(10.5 * scale)),
            cardVerticalPadding: max(6, round(6.5 * scale)),
            headerSpacing: max(5, round(6 * scale)),
            titleSize: max(9, 10 * scale),
            accessorySize: max(8.5, 9.5 * scale),
            quickActionCount: 4,
            compactActionSize: max(22, round(24 * scale))
        )
    }

    private func overviewScaledWidths(
        availableWidth: CGFloat,
        referenceWidths: [CGFloat],
        spacing: CGFloat
    ) -> [CGFloat] {
        guard !referenceWidths.isEmpty else { return [] }

        let totalSpacing = spacing * CGFloat(max(referenceWidths.count - 1, 0))
        let contentWidth = max(0, availableWidth - totalSpacing)
        let totalReferenceWidth = max(referenceWidths.reduce(0, +), 1)
        let scale = contentWidth / totalReferenceWidth
        var widths = referenceWidths.map { floor($0 * scale) }
        let remainder = contentWidth - widths.reduce(0, +)

        if let lastIndex = widths.indices.last {
            widths[lastIndex] += remainder
        }

        return widths
    }

    private var overviewSystemStatus: IslandContent.SystemStatus {
        store.currentContent.systemStatus ?? unavailableSystemStatus
    }

    private var overviewAgendaEntries: [IslandContent.CalendarDayEntry] {
        let entries = store.currentContent.calendarOverview?.entries ?? []
        let filtered = entries.filter { !$0.detail.isPlaceholder }
        return Array(filtered.prefix(2))
    }

    private var overviewRecentFiles: [OverviewRecentFile] {
        let recentURLs = Array(NSDocumentController.shared.recentDocumentURLs.prefix(3))
        if !recentURLs.isEmpty {
            return recentURLs.map { url in
                OverviewRecentFile(
                    id: url.absoluteString,
                    title: url.deletingPathExtension().lastPathComponent,
                    subtitle: overviewRelativeTimestamp(for: url),
                    url: url
                )
            }
        }

        return [
            OverviewRecentFile(id: "sample-docx", title: "项目计划", subtitle: "10:42", url: nil),
            OverviewRecentFile(id: "sample-pdf", title: "需求文档", subtitle: "昨天", url: nil),
            OverviewRecentFile(id: "sample-xlsx", title: "数据统计", subtitle: "昨天", url: nil)
        ]
    }

    private func overviewRelativeTimestamp(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modifiedAt = values?.contentModificationDate else {
            return url.pathExtension.uppercased()
        }

        if Calendar.current.isDateInToday(modifiedAt) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: modifiedAt)
        }

        if Calendar.current.isDateInYesterday(modifiedAt) {
            return "昨天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: modifiedAt)
    }

    private func overviewCard<Content: View>(
        title: String,
        icon: String? = nil,
        showsHeader: Bool = true,
        height: CGFloat,
        metrics: OverviewDashboardMetrics,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: showsHeader ? metrics.headerSpacing : 0) {
            if showsHeader {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: metrics.accessorySize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Text(title)
                        .font(.system(size: metrics.titleSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.accessorySize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            content()
        }
        .padding(.horizontal, metrics.cardHorizontalPadding)
        .padding(.vertical, metrics.cardVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.045),
                            Color.white.opacity(0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
    }

    private func overviewWeatherCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        let weather = displayedWeatherSnapshot
        let iconSize = max(28, 34 * metrics.scale)
        let sunSize = max(22, 28 * metrics.scale)
        let tempSize = max(18, 19 * metrics.scale)
        let conditionSize = max(8, 8.2 * metrics.scale)
        let citySize = max(7, 7.2 * metrics.scale)
        let leadingSlotWidth = max(54, 58 * metrics.scale)
        let baselineTopInset = max(10, 13 * metrics.scale)
        let currentSymbol = weather.hourly.first?.symbolName ?? "cloud.sun.fill"

        return Button {
            activateSection(.notification)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: baselineTopInset)

                HStack(spacing: max(6, 7 * metrics.scale)) {
                    ZStack {
                        weatherOverviewGlow(for: currentSymbol, size: sunSize)
                            .offset(x: 7 * metrics.scale, y: -6 * metrics.scale)

                        animatedWeatherSymbol(
                            currentSymbol,
                            size: iconSize,
                            weight: .medium,
                            gradient: LinearGradient(
                                colors: [.white, Color(red: 0.87, green: 0.91, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            shadowColor: .white.opacity(0.14),
                            shadowRadius: 10,
                            shadowYOffset: 4,
                            amplitude: max(1.2, 2.1 * metrics.scale),
                            emphasis: 0.028
                        )
                    }
                    .frame(width: leadingSlotWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(weather.temperature)°")
                            .font(.system(size: tempSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        Text(weather.condition)
                            .font(.system(size: conditionSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)

                        Label(weather.city, systemImage: "location")
                            .font(.system(size: citySize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius + 2, style: .continuous))
        }
        .padding(.horizontal, metrics.cardHorizontalPadding)
        .padding(.vertical, metrics.cardVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius + 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.18, blue: 0.34),
                            Color(red: 0.08, green: 0.09, blue: 0.28),
                            Color(red: 0.16, green: 0.10, blue: 0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius + 2, style: .continuous)
                .stroke(Color(red: 0.36, green: 0.31, blue: 1.0).opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.30, green: 0.24, blue: 0.92).opacity(0.24), radius: 20, y: 8)
        .buttonStyle(.plain)
        .help("打开天气面板")
    }

    private func overviewRecentFilesCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        overviewCard(title: "最近文件", showsHeader: false, height: height, metrics: metrics) {
            VStack(alignment: .leading, spacing: max(4, 4.5 * metrics.scale)) {
                ForEach(Array(overviewRecentFiles.prefix(3).enumerated()), id: \.element.id) { index, file in
                    Button {
                        openRecentFile(file)
                    } label: {
                        overviewRecentFileRow(file, metrics: metrics)
                    }
                    .buttonStyle(.plain)

                    if index < min(overviewRecentFiles.count, 3) - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func overviewRecentFileRow(_ file: OverviewRecentFile, metrics: OverviewDashboardMetrics) -> some View {
        HStack(spacing: max(7, 8 * metrics.scale)) {
            overviewFileIcon(for: file, metrics: metrics)

            VStack(alignment: .leading, spacing: max(1, 1.5 * metrics.scale)) {
                Text(overviewFileDisplayTitle(for: file))
                    .font(.system(size: max(8.4, 8.8 * metrics.scale), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.84)

                Text(overviewFileExtensionLabel(for: file))
                    .font(.system(size: max(6.4, 6.8 * metrics.scale), weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: max(6, 7 * metrics.scale))

            Text(file.subtitle)
                .font(.system(size: max(6.8, 7.1 * metrics.scale), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .padding(.horizontal, max(5, 6 * metrics.scale))
                .padding(.vertical, max(2, 2.5 * metrics.scale))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func overviewFileIcon(for file: OverviewRecentFile, metrics: OverviewDashboardMetrics) -> some View {
        let iconWidth = max(22, 24 * metrics.scale)
        let iconHeight = max(24, 26 * metrics.scale)
        let iconCornerRadius = max(7, 8.5 * metrics.scale)

        return Group {
            if let url = file.url {
                let image = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(overviewFallbackFileTint(for: file).gradient)
                    .overlay(
                        Text(overviewFallbackFileAbbreviation(for: file))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                )
            }
        }
        .frame(width: iconWidth, height: iconHeight)
        .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
    }

    private func overviewSystemStatusCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        let status = overviewSystemStatus

        return Button {
            activateSection(.status)
        } label: {
            overviewCard(title: "系统状态", showsHeader: false, height: height, metrics: metrics) {
                VStack(spacing: 5) {
                    overviewStatusRow(
                        title: status.cpu.title,
                        symbolName: "cpu",
                        accent: Color(red: 0.50, green: 0.38, blue: 1.0),
                        progress: status.cpu.progress,
                        value: status.cpu.valueText,
                        metrics: metrics
                    )

                    overviewStatusRow(
                        title: status.memory.title,
                        symbolName: "memorychip",
                        accent: Color(red: 0.33, green: 0.53, blue: 1.0),
                        progress: status.memory.progress,
                        value: status.memory.valueText,
                        metrics: metrics
                    )

                    overviewStatusRow(
                        title: "电池",
                        symbolName: batterySymbolName(for: status.battery),
                        accent: Color(red: 0.41, green: 0.84, blue: 0.43),
                        progress: (status.battery.levelPercent ?? 0) / 100,
                        value: status.battery.levelText,
                        metrics: metrics
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .help("打开状态面板")
    }

    private func overviewStatusRow(
        title: String,
        symbolName: String,
        accent: Color,
        progress: Double,
        value: String,
        metrics: OverviewDashboardMetrics
    ) -> some View {
        let rowSpacing = max(6, 6.5 * metrics.scale)
        let iconSize = max(8.5, 8.8 * metrics.scale)
        let titleSize = max(7.8, 7.9 * metrics.scale)
        let valueSize = max(7.8, 7.9 * metrics.scale)
        let titleWidth = max(22, 23 * metrics.scale)
        let valueWidth = max(28, 29 * metrics.scale)
        let barHeight = max(5.5, 5.8 * metrics.scale)

        return HStack(spacing: rowSpacing) {
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 12)

            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: titleWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(16, geometry.size.width * max(0, min(progress, 1))))
                }
            }
            .frame(height: barHeight)

            Text(value)
                .font(.system(size: valueSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .monospacedDigit()
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    private func overviewAgendaCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        Button {
            activateSection(.calendar)
        } label: {
            overviewCard(title: "今日日程", icon: "calendar", showsHeader: false, height: height, metrics: metrics) {
                VStack(spacing: 7) {
                    if overviewAgendaEntries.isEmpty {
                        Text("今天没有待处理日程")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    } else {
                        ForEach(overviewAgendaEntries) { entry in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(entry.isToday ? Color(red: 0.29, green: 0.53, blue: 1.0) : Color(red: 0.58, green: 0.33, blue: 0.96))
                                    .frame(width: 6, height: 6)

                                Text(entry.detail.timeText)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .monospacedDigit()
                                    .frame(width: 38, alignment: .leading)

                                Text(entry.detail.title)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.76))
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Color.white.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help("打开日历面板")
    }

    private func overviewNotificationCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        let headline: String
        let detail: String

        if let preview = store.notificationPreview {
            headline = "2 条未读"
            detail = preview.title
        } else if settings.notificationEnabled {
            headline = "2 条未读"
            detail = "暂无重要提醒"
        } else {
            headline = "提醒已关闭"
            detail = "不会显示横幅提醒"
        }

        return Button {
            activateSection(.settings)
        } label: {
            overviewCard(title: "通知", icon: "bell", showsHeader: false, height: height, metrics: metrics) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.24, green: 0.19, blue: 0.51).opacity(0.95))

                        Image(systemName: "bell")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.56, green: 0.48, blue: 1.0))
                    }
                    .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.system(size: 8.8, weight: .bold))
                            .foregroundStyle(.white)

                        Text(detail)
                            .font(.system(size: 7.2, weight: .medium))
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .buttonStyle(.plain)
        .help("打开设置面板")
    }

    private func overviewQuickActionsCard(height: CGFloat, metrics: OverviewDashboardMetrics) -> some View {
        overviewCard(title: "快捷应用", showsHeader: false, height: height, metrics: metrics) {
            Group {
                if appShortcuts.isEmpty {
                    Text("还没有固定快捷方式")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(appShortcuts.prefix(metrics.quickActionCount))) { shortcut in
                            Button {
                                openAppShortcut(shortcut)
                            } label: {
                                overviewQuickActionIcon(shortcut, size: metrics.compactActionSize)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func overviewQuickActionIcon(_ shortcut: AppShortcut, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
                )

            if let iconImage = appIconImage(for: shortcut, iconSize: size * 0.62) {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.62, height: size * 0.62)
            } else {
                Image(systemName: shortcut.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(shortcut.tint)
            }
        }
        .frame(width: size, height: size)
    }

    private func overviewFallbackFileTint(for file: OverviewRecentFile) -> Color {
        let suffix = overviewFileExtension(for: file).lowercased()
        switch suffix {
        case ".doc", ".docx":
            return Color(red: 0.28, green: 0.56, blue: 1.0)
        case ".pdf":
            return Color(red: 0.96, green: 0.34, blue: 0.36)
        case ".xls", ".xlsx":
            return Color(red: 0.39, green: 0.80, blue: 0.42)
        default:
            return Color.white.opacity(0.28)
        }
    }

    private func overviewFallbackFileAbbreviation(for file: OverviewRecentFile) -> String {
        let suffix = overviewFileExtension(for: file).replacingOccurrences(of: ".", with: "")
        return suffix.isEmpty ? "F" : String(suffix.prefix(1)).uppercased()
    }

    private func overviewFileExtension(for file: OverviewRecentFile) -> String {
        guard let url = file.url else {
            switch file.id {
            case "sample-docx": return ".docx"
            case "sample-pdf": return ".pdf"
            case "sample-xlsx": return ".xlsx"
            default: return ""
            }
        }

        let suffix = url.pathExtension
        return suffix.isEmpty ? "" : ".\(suffix)"
    }

    private func overviewFileDisplayTitle(for file: OverviewRecentFile) -> String {
        let suffix = overviewFileExtension(for: file)
        return file.title + suffix
    }

    private func overviewFileExtensionLabel(for file: OverviewRecentFile) -> String {
        let suffix = overviewFileExtension(for: file).replacingOccurrences(of: ".", with: "").uppercased()
        return suffix.isEmpty ? "最近访问" : suffix
    }

    private func openRecentFile(_ file: OverviewRecentFile) {
        guard let url = file.url else { return }
        NSWorkspace.shared.open(url)
    }

    private var embeddedSettingsPanel: some View {
        SettingsPanelView(settings: settings, weatherStore: weatherStore, mode: .embedded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func weatherCurrentColumn(_ weather: WeatherSnapshot, metrics: WeatherPanelMetrics) -> some View {
        let currentSymbol = weather.hourly.first?.symbolName ?? "cloud.sun.fill"

        return HStack(spacing: 8 * metrics.scale) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.40, green: 0.58, blue: 1.0).opacity(0.88),
                                Color(red: 0.22, green: 0.31, blue: 0.62).opacity(0.70)
                            ],
                            center: UnitPoint(x: 0.38, y: 0.34),
                            startRadius: 4,
                            endRadius: 54
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )

                animatedWeatherSymbol(
                    currentSymbol,
                    size: metrics.iconOrbSize * 0.5,
                    weight: .medium,
                    gradient: LinearGradient(
                        colors: [Color(red: 1.0, green: 0.86, blue: 0.44), .white, Color(red: 0.76, green: 0.86, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    shadowColor: .clear,
                    shadowRadius: 0,
                    shadowYOffset: 0,
                    amplitude: 2.2 * metrics.scale,
                    emphasis: 0.034
                )
            }
            .frame(width: metrics.iconOrbSize * 0.92, height: metrics.iconOrbSize * 0.92)
            .shadow(color: Color(red: 0.31, green: 0.44, blue: 0.98).opacity(0.38), radius: 20 * metrics.scale, y: 8 * metrics.scale)

            VStack(alignment: .leading, spacing: 1.5 * metrics.scale) {
                Text("\(weather.temperature)°")
                    .font(.system(size: metrics.currentTemperatureSize, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(weather.condition)
                    .font(.system(size: metrics.currentConditionSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Label(weather.city, systemImage: "location.fill")
                    .font(.system(size: metrics.currentMetaSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 1.5 * metrics.scale) {
                    HStack(spacing: 0) {
                        weatherMetricText("体感 \(weather.feelsLike)°", metrics: metrics)
                        weatherMetricText(" · 湿度 \(weather.humidity)%", metrics: metrics)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                    Text(weather.airQuality)
                        .font(.system(size: metrics.supportingTextSize, weight: .semibold))
                        .foregroundStyle(Color(red: 0.40, green: 0.88, blue: 0.48))
                        .lineLimit(1)
                }
                .padding(.top, 4 * metrics.scale)
            }
            .frame(minWidth: 96 * metrics.scale, maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func weatherHourlyCard(_ weather: WeatherSnapshot, metrics: WeatherPanelMetrics) -> some View {
        let currentIndex = weather.hourly.firstIndex(where: \.isCurrent) ?? 0

        return VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            HStack(spacing: 0) {
                ForEach(weather.hourly) { hour in
                    VStack(spacing: 10 * metrics.scale) {
                        Text(hour.time)
                            .font(.system(size: metrics.hourlyTimeSize, weight: hour.isCurrent ? .bold : .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(hour.isCurrent ? Color(red: 0.53, green: 0.44, blue: 1.0) : .white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        animatedWeatherSymbol(
                            hour.symbolName,
                            size: metrics.hourlyIconSize,
                            weight: .medium,
                            gradient: weatherSymbolGradient(for: hour.symbolName),
                            shadowColor: .clear,
                            shadowRadius: 0,
                            shadowYOffset: 0,
                            amplitude: hour.isCurrent ? 1.9 * metrics.scale : 1.0 * metrics.scale,
                            emphasis: hour.isCurrent ? 0.024 : 0.014
                        )

                        Text("\(hour.temperature)°")
                            .font(.system(size: metrics.hourlyTemperatureSize, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            GeometryReader { geometry in
                let indicatorWidth = 30 * metrics.scale
                let columnWidth = geometry.size.width / CGFloat(max(weather.hourly.count, 1))
                let xOffset = (columnWidth * CGFloat(currentIndex)) + ((columnWidth - indicatorWidth) / 2)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.50, green: 0.40, blue: 1.0))
                    .frame(width: indicatorWidth, height: 4 * metrics.scale)
                    .offset(x: xOffset)
            }
            .frame(height: 4 * metrics.scale)
        }
        .padding(.horizontal, metrics.cardPaddingHorizontal)
        .padding(.top, metrics.cardPaddingVertical)
        .padding(.bottom, metrics.cardPaddingVertical * 0.72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(weatherCardBackground(cornerRadius: metrics.cardCornerRadius))
    }

    private func weatherDailyCard(_ weather: WeatherSnapshot, metrics: WeatherPanelMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6 * metrics.scale) {
                    Label("\(weather.precipitationChance)%", systemImage: "drop")
                        .font(.system(size: metrics.headerTextSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: 12 * metrics.scale)

                    Label("\(weather.windSpeed) km/h", systemImage: "wind")
                        .font(.system(size: metrics.headerTextSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 6 * metrics.scale)

                HStack(spacing: 6 * metrics.scale) {
                    Text("天气")
                        .font(.system(size: metrics.currentMetaSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Image(systemName: "cloud")
                        .font(.system(size: metrics.currentMetaSize * 1.18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(.bottom, metrics.dailyHeaderBottomSpacing)

            ForEach(Array(weather.daily.enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text(day.weekday)
                        .font(.system(size: metrics.dayTextSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 34 * metrics.scale, alignment: .leading)

                    Spacer(minLength: 5 * metrics.scale)

                    animatedWeatherSymbol(
                        day.symbolName,
                        size: metrics.hourlyIconSize * 0.9,
                        weight: .medium,
                        gradient: weatherSymbolGradient(for: day.symbolName),
                        shadowColor: .clear,
                        shadowRadius: 0,
                        shadowYOffset: 0,
                        amplitude: 0.8 * metrics.scale,
                        emphasis: 0.012
                    )

                    Spacer(minLength: 8 * metrics.scale)

                    Text("\(day.high)° / \(day.low)°")
                        .font(.system(size: metrics.dayTextSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(height: metrics.dayRowHeight)

                if index < weather.daily.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.cardPaddingHorizontal)
        .padding(.vertical, metrics.cardPaddingVertical * 0.86)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(weatherCardBackground(cornerRadius: metrics.cardCornerRadius))
    }

    private func weatherMetricText(_ text: String, metrics: WeatherPanelMetrics) -> some View {
        Text(text)
            .font(.system(size: metrics.supportingTextSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.54))
    }

    private func weatherCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.075),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
    }

    private func weatherOverviewGlow(for symbolName: String, size: CGFloat) -> some View {
        switch WeatherSymbolKind(symbolName: symbolName) {
        case .sunny, .sunCloud:
            return AnyView(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.88, blue: 0.42),
                                Color(red: 0.99, green: 0.70, blue: 0.18).opacity(0.22)
                            ],
                            center: UnitPoint(x: 0.72, y: 0.28),
                            startRadius: 6,
                            endRadius: 54
                        )
                    )
                    .frame(width: size, height: size)
            )
        case .rainy, .storm:
            return AnyView(
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.58, green: 0.77, blue: 1.0).opacity(0.58),
                                Color(red: 0.34, green: 0.50, blue: 0.94).opacity(0.05)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 48
                        )
                    )
                    .frame(width: size * 1.08, height: size * 0.82)
            )
        case .cloudy, .snow:
            return AnyView(
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.26),
                                Color(red: 0.72, green: 0.82, blue: 1.0).opacity(0.04)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 42
                        )
                    )
                    .frame(width: size * 1.04, height: size * 0.76)
            )
        case .moon:
            return AnyView(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.56, green: 0.66, blue: 1.0).opacity(0.56),
                                Color(red: 0.30, green: 0.36, blue: 0.82).opacity(0.06)
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 46
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.92)
            )
        case .generic:
            return AnyView(
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size * 0.82, height: size * 0.82)
            )
        }
    }

    private func animatedWeatherSymbol(
        _ systemName: String,
        size: CGFloat,
        weight: Font.Weight,
        gradient: LinearGradient,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat,
        amplitude: CGFloat,
        emphasis: CGFloat
    ) -> some View {
        let _ = weight
        let _ = amplitude
        let _ = emphasis

        return WeatherAnimatedSymbol(
            symbolName: systemName,
            size: size,
            gradient: gradient,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            shadowYOffset: shadowYOffset,
            isAnimated: store.animationsEnabled
        )
    }

    private func weatherSymbolGradient(for symbolName: String) -> LinearGradient {
        if symbolName.contains("moon") {
            return LinearGradient(
                colors: [Color(red: 0.74, green: 0.81, blue: 1.0), Color(red: 0.46, green: 0.56, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if symbolName.contains("rain") {
            return LinearGradient(
                colors: [Color.white, Color(red: 0.54, green: 0.75, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if symbolName.contains("sun") {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.84, blue: 0.36), Color(red: 1.0, green: 0.92, blue: 0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.white, Color(red: 0.82, green: 0.89, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func shortcutCard(_ shortcut: AppShortcut, metrics: ShortcutPanelMetrics) -> some View {
        let isHovered = hoveredShortcutID == shortcut.id
        let isHighlighted = isHovered

        return Button {
            openAppShortcut(shortcut)
        } label: {
            VStack(spacing: metrics.cardContentSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    shortcut.tint.opacity(isHighlighted ? 0.24 : 0.16),
                                    Color.white.opacity(isHighlighted ? 0.08 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: metrics.iconContainerSize, height: metrics.iconContainerSize)

                    shortcutIcon(shortcut, metrics: metrics)
                }

                Text(shortcut.title)
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.cardHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHighlighted ? 0.085 : 0.045),
                                Color.white.opacity(isHighlighted ? 0.03 : 0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .stroke(
                        isHighlighted
                            ? Color(red: 0.43, green: 0.31, blue: 1.0).opacity(0.95)
                            : Color.white.opacity(0.05),
                        lineWidth: isHighlighted ? 1.4 : 0.8
                    )
            )
            .shadow(
                color: isHighlighted
                    ? Color(red: 0.38, green: 0.28, blue: 1.0).opacity(0.26)
                    : .clear,
                radius: 16,
                y: 6
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .onHover { isHovering in
            hoveredShortcutID = isHovering ? shortcut.id : nil
        }
    }

    private var emptyShortcutState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))

            Text("还没有固定快捷方式")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text("在设置页勾选要展示的应用")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.44))
        }
    }

    private func shortcutPanelMetrics(for size: CGSize) -> ShortcutPanelMetrics {
        let columnCount = size.width < 520 ? 3 : 4
        let rowCount = ceil(Double(appShortcuts.count) / Double(columnCount))
        let compactHeight = size.height < 186
        let gridSpacing: CGFloat = compactHeight ? 7 : 10
        let sectionSpacing: CGFloat = compactHeight ? 7 : 10
        let headerBottomSpacing: CGFloat = compactHeight ? 0 : 2
        let headerHeight: CGFloat = compactHeight ? 16 : 18
        let totalGridSpacing = gridSpacing * CGFloat(max(rowCount - 1, 0))
        let reservedHeight = headerHeight + headerBottomSpacing + sectionSpacing
        let availableGridHeight = max(88, size.height - reservedHeight)
        let cardHeight = min(90, max(40, floor((availableGridHeight - totalGridSpacing) / CGFloat(max(rowCount, 1)))))
        let compactCard = cardHeight < 60

        return ShortcutPanelMetrics(
            columnCount: columnCount,
            gridSpacing: gridSpacing,
            sectionSpacing: sectionSpacing,
            headerBottomSpacing: headerBottomSpacing,
            headerHeight: headerHeight,
            cardHeight: cardHeight,
            cardContentSpacing: compactCard ? 5 : 8,
            iconContainerSize: compactCard ? 28 : 40,
            iconSize: compactCard ? 15 : 21,
            titleSize: compactCard ? 9 : 10,
            cardCornerRadius: compactCard ? 16 : 22,
            dockHeight: 0,
            dockHorizontalPadding: 0,
            dockIconSize: 0,
            activeDockWidth: 0,
            activeDockHeight: 0
        )
    }

    @ViewBuilder
    private func shortcutIcon(_ shortcut: AppShortcut, metrics: ShortcutPanelMetrics) -> some View {
        if let appIcon = appIconImage(for: shortcut, iconSize: metrics.iconContainerSize * 0.86) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: metrics.iconContainerSize * 0.86, height: metrics.iconContainerSize * 0.86)
                .clipShape(RoundedRectangle(cornerRadius: metrics.iconContainerSize * 0.22, style: .continuous))
        } else {
            Image(systemName: shortcut.symbolName)
                .font(.system(size: metrics.iconSize, weight: .medium))
                .foregroundStyle(shortcut.tint)
        }
    }

    private func appIconImage(for shortcut: AppShortcut, iconSize: CGFloat) -> NSImage? {
        let appURL: URL?
        if let appPath = shortcut.appPath {
            appURL = URL(fileURLWithPath: appPath)
        } else if let bundleIdentifier = shortcut.bundleIdentifier {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        } else {
            appURL = nil
        }

        guard let appURL else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: iconSize, height: iconSize)
        return icon
    }

    private func openAppShortcut(_ shortcut: AppShortcut) {
        let appURL: URL?
        if let appPath = shortcut.appPath {
            appURL = URL(fileURLWithPath: appPath)
        } else if let bundleIdentifier = shortcut.bundleIdentifier {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        } else {
            appURL = nil
        }

        guard let appURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: IslandSpacing.xSmall + 1) {
                    ForEach(displayedAgendaEntries) { entry in
                        agendaEventCard(entry, metrics: metrics)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(calendarMetaText(for: entry))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
        return events.isEmpty ? Array(calendarEntries.prefix(1)) : events
    }

    private var displayedAgendaEntries: [IslandContent.CalendarDayEntry] {
        agendaEntries
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
            agendaCardMinHeight: IslandLayout.clamp(56 * scale, min: 52, max: 68),
            calendarCellSize: IslandLayout.clamp(monthWidth / 12, min: 14, max: 17),
            dotSize: IslandLayout.clamp(1.5 * scale, min: 1.5, max: 2.2),
            badgeHeight: IslandLayout.clamp(18 * scale, min: 16, max: 20)
        )
    }

    private func weatherPanelMetrics(for availableSize: CGSize) -> WeatherPanelMetrics {
        let verticalBudget = max(availableSize.height - 10, 0)
        let scale = IslandLayout.clamp(
            min(availableSize.width / 640, availableSize.height / 170),
            min: 0.58,
            max: 1.0
        )
        let spacing = 10 * scale
        let cardHeight = IslandLayout.clamp(verticalBudget * 0.84, min: 118 * scale, max: 164 * scale)
        let currentMinWidth = IslandLayout.clamp(146 * scale, min: 130, max: 164)
        let currentIdealWidth = IslandLayout.clamp(204 * scale, min: 182, max: 220)
        let hourlyMinWidth = IslandLayout.clamp(258 * scale, min: 228, max: 292)
        let hourlyIdealWidth = IslandLayout.clamp(304 * scale, min: 272, max: 332)
        let dailyMinWidth = IslandLayout.clamp(154 * scale, min: 138, max: 174)
        let dailyIdealWidth = IslandLayout.clamp(196 * scale, min: 176, max: 212)
        let iconOrbSize = IslandLayout.clamp(82 * scale, min: 64, max: 84)
        let currentTemperatureSize = IslandLayout.clamp(38 * scale, min: 28, max: 40)
        let currentConditionSize = IslandLayout.clamp(14.5 * scale, min: 10.5, max: 15)
        let currentMetaSize = IslandLayout.clamp(10.5 * scale, min: 8.8, max: 10.5)
        let supportingTextSize = IslandLayout.clamp(8.4 * scale, min: 7.0, max: 8.4)
        let headerTextSize = IslandLayout.clamp(8.8 * scale, min: 7.2, max: 8.8)
        let hourlyIconSize = IslandLayout.clamp(20 * scale, min: 15, max: 20)
        let hourlyTimeSize = IslandLayout.clamp(8.6 * scale, min: 7.2, max: 8.6)
        let hourlyTemperatureSize = IslandLayout.clamp(15.5 * scale, min: 11.5, max: 15.5)
        let dailyHeaderBottomSpacing = IslandLayout.clamp(cardHeight * 0.07, min: 5 * scale, max: 10 * scale)
        let dayRowHeight = IslandLayout.clamp((cardHeight - 34 * scale) / 3, min: 24, max: 35)
        let dayTextSize = IslandLayout.clamp(11.2 * scale, min: 9.2, max: 11.2)
        let cardPaddingHorizontal = IslandLayout.clamp(13 * scale, min: 9, max: 13)
        let cardPaddingVertical = IslandLayout.clamp(11.5 * scale, min: 8, max: 11.5)
        let cardCornerRadius = IslandLayout.clamp(20 * scale, min: 14, max: 20)

        return WeatherPanelMetrics(
            scale: scale,
            spacing: spacing,
            cardHeight: cardHeight,
            currentMinWidth: currentMinWidth,
            currentIdealWidth: currentIdealWidth,
            hourlyMinWidth: hourlyMinWidth,
            hourlyIdealWidth: hourlyIdealWidth,
            dailyMinWidth: dailyMinWidth,
            dailyIdealWidth: dailyIdealWidth,
            iconOrbSize: iconOrbSize,
            currentTemperatureSize: currentTemperatureSize,
            currentConditionSize: currentConditionSize,
            currentMetaSize: currentMetaSize,
            supportingTextSize: supportingTextSize,
            headerTextSize: headerTextSize,
            hourlyIconSize: hourlyIconSize,
            hourlyTimeSize: hourlyTimeSize,
            hourlyTemperatureSize: hourlyTemperatureSize,
            dayRowHeight: dayRowHeight,
            dayTextSize: dayTextSize,
            dailyHeaderBottomSpacing: dailyHeaderBottomSpacing,
            cardPaddingHorizontal: cardPaddingHorizontal,
            cardPaddingVertical: cardPaddingVertical,
            cardCornerRadius: cardCornerRadius
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
    }(), settings: AppSettingsStore(), weatherStore: WeatherStore())
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
    }(), settings: AppSettingsStore(), weatherStore: WeatherStore(), initialSection: .notification)
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
