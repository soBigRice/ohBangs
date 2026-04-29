import Foundation

struct IslandContent: Sendable {
    struct CalendarEventDetail: Sendable {
        let title: String
        let timeText: String
        let detailText: String
        let statusText: String
        let symbolName: String
        let isPlaceholder: Bool
    }

    struct CalendarDayEntry: Sendable, Identifiable {
        let id: String
        let monthText: String
        let dayText: String
        let weekdayText: String
        let isToday: Bool
        let hasEvents: Bool
        let detail: CalendarEventDetail
    }

    struct CalendarOverview: Sendable {
        let title: String
        let entries: [CalendarDayEntry]
        let suggestedEntryID: String
    }

    struct CalendarSummary: Sendable {
        let monthText: String
        let dayText: String
        let weekdayText: String
        let eventTitle: String
        let timeText: String
        let detailText: String
        let statusText: String
        let isPlaceholder: Bool
    }

    let appName: String
    let title: String
    let subtitle: String
    let isLive: Bool
    let calendarSummary: CalendarSummary?
    let calendarOverview: CalendarOverview?
}

protocol IslandContentProvider: AnyObject {
    func start(onUpdate: @escaping (IslandContent) -> Void)
    func stop()
}

final class MockIslandContentProvider: IslandContentProvider {
    private var timerTask: Task<Void, Never>?
    private let messages: [IslandContent] = [
        IslandContent(appName: "ohBangs", title: "番茄钟进行中", subtitle: "剩余 24:59", isLive: true, calendarSummary: nil, calendarOverview: nil),
        IslandContent(appName: "ohBangs", title: "同步任务中", subtitle: "iCloud Drive", isLive: true, calendarSummary: nil, calendarOverview: nil),
        IslandContent(appName: "ohBangs", title: "收到新消息", subtitle: "来自开发助手", isLive: false, calendarSummary: nil, calendarOverview: nil)
    ]

    func start(onUpdate: @escaping (IslandContent) -> Void) {
        stop()

        timerTask = Task {
            var index = 0
            await MainActor.run {
                onUpdate(messages[index])
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                index = (index + 1) % messages.count
                await MainActor.run {
                    onUpdate(messages[index])
                }
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }
}
