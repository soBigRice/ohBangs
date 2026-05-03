import Combine
import Foundation

@MainActor
final class IslandStateStore: ObservableObject {
    struct NotificationPreview: Equatable {
        let iconSystemName: String
        let title: String
        let subtitle: String
    }

    enum DisplayState {
        case collapsed
        case hint
        case expanded
    }

    @Published private(set) var displayState: DisplayState = .collapsed
    @Published private(set) var isHovering: Bool = false
    @Published private(set) var currentContent = IslandContent(
        appName: "日历",
        title: "正在读取系统日历",
        subtitle: "首次启动可能会请求权限",
        isLive: true,
        calendarSummary: nil,
        calendarOverview: nil
    )
    @Published private(set) var notificationPreview: NotificationPreview?
    @Published var animationsEnabled: Bool = true

    private var autoCollapseTask: Task<Void, Never>?
    private var notificationDismissTask: Task<Void, Never>?
    private let autoCollapseDuration: Duration = .seconds(4)
    private var isPinnedExpanded = false
    var notificationPreviewDuration: Duration = .seconds(3)

    var isCollapsed: Bool { displayState == .collapsed }
    var isHint: Bool { displayState == .hint }
    var isExpanded: Bool { displayState == .expanded }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering

        switch displayState {
        case .collapsed where hovering:
            displayState = .hint
        case .hint where !hovering:
            displayState = .collapsed
        case .expanded where !hovering:
            if !isPinnedExpanded {
                collapse()
            }
        default:
            break
        }
    }

    func expand() {
        displayState = .expanded
        scheduleAutoCollapse()
    }

    func collapse() {
        displayState = isHovering ? .hint : .collapsed
        cancelAutoCollapseTask()
    }

    func toggle() {
        switch displayState {
        case .collapsed, .hint:
            expand()
        case .expanded:
            collapse()
        }
    }

    func updateContent(_ content: IslandContent) {
        currentContent = content
    }

    func toggleAnimations() {
        animationsEnabled.toggle()
    }

    func setSettingsPanelPresented(_ presented: Bool) {
        isPinnedExpanded = presented

        if presented {
            displayState = .expanded
            cancelAutoCollapseTask()
        } else if displayState == .expanded && !isHovering {
            collapse()
        }
    }

    func presentNotification(title: String, subtitle: String, iconSystemName: String = "bell.badge.fill") {
        notificationDismissTask?.cancel()
        notificationPreview = NotificationPreview(
            iconSystemName: iconSystemName,
            title: title,
            subtitle: subtitle
        )

        notificationDismissTask = Task { [weak self] in
            try? await Task.sleep(for: self?.notificationPreviewDuration ?? .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.notificationPreview = nil
            }
        }
    }

    private func scheduleAutoCollapse() {
        cancelAutoCollapseTask()
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autoCollapseDuration ?? .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isPinnedExpanded, !self.isHovering else { return }
                self.collapse()
            }
        }
    }

    private func cancelAutoCollapseTask() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}
