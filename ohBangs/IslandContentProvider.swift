import Foundation

struct IslandContent: Sendable {
    struct SystemStatus: Sendable {
        struct Primary: Sendable {
            let machineName: String
            let operatingSystem: String
            let chipName: String
            let memoryCapacityText: String
            let storageCapacityText: String
        }

        struct Metric: Sendable {
            let title: String
            let valueText: String
            let detailText: String
            let footerText: String
            let progress: Double
            let history: [Double]
        }

        struct Network: Sendable {
            let networkName: String
            let bandText: String
            let uploadRateBytesPerSecond: Double
            let downloadRateBytesPerSecond: Double
            let uploadHistory: [Double]
            let downloadHistory: [Double]
        }

        struct Battery: Sendable {
            let levelPercent: Double?
            let levelText: String
            let statusText: String
            let timeRemainingText: String
            let isCharging: Bool
        }

        let primary: Primary
        let cpu: Metric
        let memory: Metric
        let storage: Metric
        let thermal: Metric
        let network: Network
        let battery: Battery
    }

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
    let systemStatus: SystemStatus?

    init(
        appName: String,
        title: String,
        subtitle: String,
        isLive: Bool,
        calendarSummary: CalendarSummary?,
        calendarOverview: CalendarOverview?,
        systemStatus: SystemStatus? = nil
    ) {
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.isLive = isLive
        self.calendarSummary = calendarSummary
        self.calendarOverview = calendarOverview
        self.systemStatus = systemStatus
    }
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
