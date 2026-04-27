import Combine
import Foundation

@MainActor
final class IslandStateStore: ObservableObject {
    enum DisplayState {
        case collapsed
        case hint
        case expanded
    }

    @Published private(set) var displayState: DisplayState = .collapsed
    @Published private(set) var isHovering: Bool = false
    @Published private(set) var currentContent = IslandContent(
        appName: "ohBangs",
        title: "Dynamic Island 已激活",
        subtitle: "等待数据源",
        isLive: true
    )
    @Published var animationsEnabled: Bool = true

    private var autoCollapseTask: Task<Void, Never>?
    private let autoCollapseDuration: Duration = .seconds(4)

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
            collapse()
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

    private func scheduleAutoCollapse() {
        cancelAutoCollapseTask()
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autoCollapseDuration ?? .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.collapse()
            }
        }
    }

    private func cancelAutoCollapseTask() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }
}
