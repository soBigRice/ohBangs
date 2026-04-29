import EventKit
import Foundation

@MainActor
final class SystemCalendarContentProvider: IslandContentProvider {
    private let eventStore = EKEventStore()
    private var refreshTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?
    private var onUpdate: ((IslandContent) -> Void)?

    func start(onUpdate: @escaping (IslandContent) -> Void) {
        stop()
        self.onUpdate = onUpdate

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshContent()
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }

            await self.refreshContent()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self.refreshContent()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil

        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }

        onUpdate = nil
    }

    private func refreshContent() async {
        let content = await loadContent()
        onUpdate?(content)
    }

    private func loadContent() async -> IslandContent {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized:
            return makeCalendarContent()
        case .notDetermined:
            let granted = await requestCalendarAccess()
            return granted ? makeCalendarContent() : makeDeniedContent()
        case .writeOnly:
            return makeNoReadAccessContent()
        case .denied, .restricted:
            return makeDeniedContent()
        @unknown default:
            return makeUnavailableContent()
        }
    }

    private func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    private func makeCalendarContent() -> IslandContent {
        let now = Date()
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(byAdding: .day, value: 14, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)

        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }

        let overview = makeCalendarOverview(from: events, now: now)
        guard let firstEntry = overview.entries.first else {
            return makeEmptyCalendarContent(now: now)
        }

        let summary = makeSummary(from: firstEntry)
        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: true,
            calendarSummary: summary,
            calendarOverview: overview
        )
    }

    private func preferredEvent(in events: [EKEvent], now: Date) -> EKEvent? {
        if let current = events.first(where: { $0.startDate <= now && $0.endDate > now }) {
            return current
        }
        return events.first(where: { $0.startDate >= now })
    }

    private func makeCalendarOverview(from events: [EKEvent], now: Date) -> IslandContent.CalendarOverview {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let entries = (0..<7).compactMap { offset -> IslandContent.CalendarDayEntry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let dayEvents = eventsForDay(day, from: events, calendar: calendar)
            return makeDayEntry(for: day, events: dayEvents, now: now)
        }

        let suggestedEntryID = entries.first(where: { $0.detail.statusText == "进行中" })?.id
            ?? entries.first(where: { $0.hasEvents })?.id
            ?? entries.first?.id
            ?? today.formatted(.iso8601.year().month().day())

        return IslandContent.CalendarOverview(
            title: "系统日历",
            entries: entries,
            suggestedEntryID: suggestedEntryID
        )
    }

    private func makeDayEntry(for day: Date, events: [EKEvent], now: Date) -> IslandContent.CalendarDayEntry {
        let monthText = day.formatted(.dateTime.month(.defaultDigits)) + "月"
        let dayText = day.formatted(.dateTime.day())
        let weekdayText = compactWeekdayLabel(for: day)
        let isToday = Calendar.current.isDateInToday(day)

        if let event = preferredEventForDay(events, day: day, now: now) {
            return IslandContent.CalendarDayEntry(
                id: dayIdentifier(for: day),
                monthText: monthText,
                dayText: dayText,
                weekdayText: weekdayText,
                isToday: isToday,
                hasEvents: true,
                detail: makeDetail(for: event, day: day, now: now)
            )
        }

        return IslandContent.CalendarDayEntry(
            id: dayIdentifier(for: day),
            monthText: monthText,
            dayText: dayText,
            weekdayText: weekdayText,
            isToday: isToday,
            hasEvents: false,
            detail: emptyDetail(for: day, isToday: isToday)
        )
    }

    private func makeSummary(from entry: IslandContent.CalendarDayEntry) -> IslandContent.CalendarSummary {
        IslandContent.CalendarSummary(
            monthText: entry.monthText,
            dayText: entry.dayText,
            weekdayText: entry.weekdayText,
            eventTitle: entry.detail.title,
            timeText: entry.detail.timeText,
            detailText: entry.detail.detailText,
            statusText: entry.detail.statusText,
            isPlaceholder: entry.detail.isPlaceholder
        )
    }

    private func makeDetail(for event: EKEvent, day: Date, now: Date) -> IslandContent.CalendarEventDetail {
        let startDate = event.startDate ?? day
        let endDate = event.endDate ?? startDate
        let isOngoing = startDate <= now && endDate > now
        let statusText: String

        if isOngoing {
            statusText = "进行中"
        } else if Calendar.current.isDateInToday(day) {
            statusText = "今天"
        } else {
            statusText = "安排"
        }

        return IslandContent.CalendarEventDetail(
            title: event.title.nilIfEmpty ?? "未命名日程",
            timeText: timeText(for: event),
            detailText: detailText(for: event, now: now),
            statusText: statusText,
            symbolName: symbolName(for: event),
            isPlaceholder: false
        )
    }

    private func emptyDetail(for day: Date, isToday: Bool) -> IslandContent.CalendarEventDetail {
        IslandContent.CalendarEventDetail(
            title: isToday ? "今天暂无安排" : "这一天暂无安排",
            timeText: "左右滑动查看别的日期",
            detailText: isToday ? "可以专注处理手头事务" : "系统日历里没有读取到事件",
            statusText: isToday ? "空闲" : "无日程",
            symbolName: "sparkles",
            isPlaceholder: true
        )
    }

    private func makeEmptyCalendarContent(now: Date) -> IslandContent {
        let day = makeDayEntry(for: now, events: [], now: now)
        let overview = IslandContent.CalendarOverview(
            title: "系统日历",
            entries: [day],
            suggestedEntryID: day.id
        )
        let summary = makeSummary(from: day)

        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: false,
            calendarSummary: summary,
            calendarOverview: overview
        )
    }

    private func makeDeniedContent() -> IslandContent {
        let overview = placeholderOverview(
            title: "需要日历权限",
            time: "打开设置授权后可显示系统日程",
            detail: "请在系统设置中允许 ohBangs 访问你的日历",
            status: "未授权"
        )
        let summary = makeSummary(from: overview.entries[0])

        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: false,
            calendarSummary: summary,
            calendarOverview: overview
        )
    }

    private func makeNoReadAccessContent() -> IslandContent {
        let overview = placeholderOverview(
            title: "当前只有写入权限",
            time: "还不能读取系统日历",
            detail: "需要完整日历权限才能展示事件内容",
            status: "权限不足"
        )
        let summary = makeSummary(from: overview.entries[0])

        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: false,
            calendarSummary: summary,
            calendarOverview: overview
        )
    }

    private func makeUnavailableContent() -> IslandContent {
        let overview = placeholderOverview(
            title: "日历暂时不可用",
            time: "稍后会自动重试",
            detail: "数据源初始化失败或系统暂未返回日历内容",
            status: "异常"
        )
        let summary = makeSummary(from: overview.entries[0])

        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: false,
            calendarSummary: summary,
            calendarOverview: overview
        )
    }

    private func placeholderOverview(title: String, time: String, detail: String, status: String) -> IslandContent.CalendarOverview {
        let now = Date()
        let entry = IslandContent.CalendarDayEntry(
            id: dayIdentifier(for: now),
            monthText: now.formatted(.dateTime.month(.defaultDigits)) + "月",
            dayText: now.formatted(.dateTime.day()),
            weekdayText: compactWeekdayLabel(for: now),
            isToday: true,
            hasEvents: false,
            detail: IslandContent.CalendarEventDetail(
                title: title,
                timeText: time,
                detailText: detail,
                statusText: status,
                symbolName: "calendar",
                isPlaceholder: true
            )
        )

        return IslandContent.CalendarOverview(
            title: "系统日历",
            entries: [entry],
            suggestedEntryID: entry.id
        )
    }

    private func eventsForDay(_ day: Date, from events: [EKEvent], calendar: Calendar) -> [EKEvent] {
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return events.filter { event in
            let startDate = event.startDate ?? day
            let endDate = event.endDate ?? startDate
            return startDate < endOfDay && endDate > day
        }
    }

    private func preferredEventForDay(_ events: [EKEvent], day: Date, now: Date) -> EKEvent? {
        if let current = events.first(where: {
            let startDate = $0.startDate ?? day
            let endDate = $0.endDate ?? startDate
            return startDate <= now && endDate > now
        }) {
            return current
        }

        let upcoming = events
            .filter { ($0.startDate ?? day) >= now }
            .sorted { ($0.startDate ?? day) < ($1.startDate ?? day) }
        if let upcoming = upcoming.first {
            return upcoming
        }

        return events.sorted { ($0.startDate ?? day) < ($1.startDate ?? day) }.first
    }

    private func timeText(for event: EKEvent) -> String {
        if event.isAllDay {
            return "全天"
        }

        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate
        let formatter = DateIntervalFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: startDate, to: endDate)
    }

    private func detailText(for event: EKEvent, now: Date) -> String {
        let startDate = event.startDate ?? now
        let endDate = event.endDate ?? startDate
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = .current
        relativeFormatter.unitsStyle = .full

        if startDate <= now && endDate > now {
            return "\(event.calendar.title) · 结束于\(relativeFormatter.localizedString(for: endDate, relativeTo: now))"
        }

        if Calendar.current.isDateInToday(startDate) {
            return "\(event.calendar.title) · 今天\(startDate.formatted(.dateTime.hour().minute()))"
        }

        return "\(event.calendar.title) · \(startDate.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)))"
    }

    private func symbolName(for event: EKEvent) -> String {
        if event.isAllDay {
            return "calendar.badge.clock"
        }

        let title = event.title?.lowercased() ?? ""
        if title.contains("会议") || title.contains("meeting") {
            return "video"
        }
        if title.contains("生日") {
            return "gift"
        }
        return "calendar"
    }

    private func dayIdentifier(for date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private func weekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return labels[max(0, min(labels.count - 1, weekday - 1))]
    }

    private func compactWeekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return labels[max(0, min(labels.count - 1, weekday - 1))]
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
