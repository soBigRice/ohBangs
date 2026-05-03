import CoreWLAN
import EventKit
import Foundation
import IOKit.ps

@MainActor
final class SystemCalendarContentProvider: IslandContentProvider {
    private struct NetworkSample {
        let receivedBytes: UInt64
        let sentBytes: UInt64
        let timestamp: TimeInterval
    }

    private let eventStore = EKEventStore()
    private var refreshTask: Task<Void, Never>?
    private var changeObserver: NSObjectProtocol?
    private var onUpdate: ((IslandContent) -> Void)?
    private var previousCPUTicks: [UInt64]?
    private var previousNetworkSample: NetworkSample?
    private var cpuHistory: [Double] = []
    private var memoryHistory: [Double] = []
    private var uploadHistory: [Double] = []
    private var downloadHistory: [Double] = []

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
                try? await Task.sleep(for: .seconds(5))
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
        let systemStatus = makeSystemStatus()
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized:
            return makeCalendarContent(systemStatus: systemStatus)
        case .notDetermined:
            let granted = await requestCalendarAccess()
            return granted ? makeCalendarContent(systemStatus: systemStatus) : makeDeniedContent(systemStatus: systemStatus)
        case .writeOnly:
            return makeNoReadAccessContent(systemStatus: systemStatus)
        case .denied, .restricted:
            return makeDeniedContent(systemStatus: systemStatus)
        @unknown default:
            return makeUnavailableContent(systemStatus: systemStatus)
        }
    }

    private func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    private func makeCalendarContent(systemStatus: IslandContent.SystemStatus) -> IslandContent {
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
            return makeEmptyCalendarContent(now: now, systemStatus: systemStatus)
        }

        let summary = makeSummary(from: firstEntry)
        return IslandContent(
            appName: overview.title,
            title: summary.eventTitle,
            subtitle: summary.timeText,
            isLive: true,
            calendarSummary: summary,
            calendarOverview: overview,
            systemStatus: systemStatus
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

    private func makeEmptyCalendarContent(now: Date, systemStatus: IslandContent.SystemStatus) -> IslandContent {
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
            calendarOverview: overview,
            systemStatus: systemStatus
        )
    }

    private func makeDeniedContent(systemStatus: IslandContent.SystemStatus) -> IslandContent {
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
            calendarOverview: overview,
            systemStatus: systemStatus
        )
    }

    private func makeNoReadAccessContent(systemStatus: IslandContent.SystemStatus) -> IslandContent {
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
            calendarOverview: overview,
            systemStatus: systemStatus
        )
    }

    private func makeUnavailableContent(systemStatus: IslandContent.SystemStatus) -> IslandContent {
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
            calendarOverview: overview,
            systemStatus: systemStatus
        )
    }

    private func makeSystemStatus() -> IslandContent.SystemStatus {
        let primary = makePrimaryStatus()
        let cpuPercent = readCPUUsagePercent()
        let memory = readMemoryStatus()
        let storage = readStorageStatus()
        let thermal = readThermalStatus()
        let network = readNetworkStatus()
        let battery = readBatteryStatus()

        cpuHistory = appendHistory(cpuPercent / 100, to: cpuHistory)
        memoryHistory = appendHistory(memory.percent / 100, to: memoryHistory)
        uploadHistory = appendHistory(network.uploadRateBytesPerSecond, to: uploadHistory)
        downloadHistory = appendHistory(network.downloadRateBytesPerSecond, to: downloadHistory)

        return IslandContent.SystemStatus(
            primary: primary,
            cpu: .init(
                title: "CPU",
                valueText: percentText(cpuPercent),
                detailText: "\(ProcessInfo.processInfo.processorCount) 核心",
                footerText: "",
                progress: cpuPercent / 100,
                history: cpuHistory
            ),
            memory: .init(
                title: "内存",
                valueText: percentText(memory.percent),
                detailText: "\(byteText(memory.usedBytes)) / \(byteText(memory.totalBytes))",
                footerText: "",
                progress: memory.percent / 100,
                history: memoryHistory
            ),
            storage: .init(
                title: "存储空间",
                valueText: percentText(storage.percent),
                detailText: "\(byteText(storage.usedBytes)) / \(byteText(storage.totalBytes))",
                footerText: "\(byteText(storage.usedBytes)) / \(byteText(storage.totalBytes))",
                progress: storage.percent / 100,
                history: []
            ),
            thermal: .init(
                title: "热压",
                valueText: thermal.label,
                detailText: thermal.detailText,
                footerText: "",
                progress: thermal.progress,
                history: []
            ),
            network: .init(
                networkName: network.name,
                bandText: network.band,
                uploadRateBytesPerSecond: network.uploadRateBytesPerSecond,
                downloadRateBytesPerSecond: network.downloadRateBytesPerSecond,
                uploadHistory: uploadHistory,
                downloadHistory: downloadHistory
            ),
            battery: battery
        )
    }

    private func makePrimaryStatus() -> IslandContent.SystemStatus.Primary {
        IslandContent.SystemStatus.Primary(
            machineName: Host.current().localizedName ?? hardwareModelIdentifier(),
            operatingSystem: operatingSystemName(),
            chipName: chipName(),
            memoryCapacityText: byteText(ProcessInfo.processInfo.physicalMemory),
            storageCapacityText: byteText(readStorageStatus().totalBytes)
        )
    }

    private func readCPUUsagePercent() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let ticks: [UInt64] = [
            UInt64(info.cpu_ticks.0),
            UInt64(info.cpu_ticks.1),
            UInt64(info.cpu_ticks.2),
            UInt64(info.cpu_ticks.3)
        ]
        defer { previousCPUTicks = ticks }

        guard let previousCPUTicks, previousCPUTicks.count == ticks.count else { return 0 }
        let deltas = zip(ticks, previousCPUTicks).map(-)
        let total = deltas.reduce(0, +)
        guard total > 0 else { return 0 }

        let inUse = deltas[0] + deltas[1] + deltas[3]
        return min(max(Double(inUse) / Double(total) * 100, 0), 100)
    }

    private func readMemoryStatus() -> (usedBytes: UInt64, totalBytes: UInt64, percent: Double) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var statistics = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, totalBytes, 0) }

        // Inactive pages are largely reclaimable cache and make the number look
        // consistently inflated. Use the closer-to-Activity-Monitor footprint.
        let usedPages = UInt64(statistics.active_count + statistics.wire_count + statistics.compressor_page_count)
        let usedBytes = usedPages * UInt64(vm_kernel_page_size)
        let percent = totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100) : 0
        return (usedBytes, totalBytes, percent)
    }

    private func readStorageStatus() -> (usedBytes: UInt64, totalBytes: UInt64, percent: Double) {
        let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let totalBytes = (values?[.systemSize] as? NSNumber)?.uint64Value ?? 0
        let freeBytes = (values?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        let percent = totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100) : 0
        return (usedBytes, totalBytes, percent)
    }

    private func readThermalStatus() -> (label: String, detailText: String, progress: Double) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return ("正常", "系统温度稳定", 0.22)
        case .fair:
            return ("偏高", "有轻微热量压力", 0.48)
        case .serious:
            return ("较高", "系统可能开始降频", 0.76)
        case .critical:
            return ("严重", "系统热压力很高", 1.0)
        @unknown default:
            return ("未知", "系统没有返回热压状态", 0.12)
        }
    }

    private func readNetworkStatus() -> (name: String, band: String, uploadRateBytesPerSecond: Double, downloadRateBytesPerSecond: Double) {
        let interface = CWWiFiClient.shared().interface()
        let interfaceName = interface?.interfaceName ?? "en0"
        let sample = readNetworkSample(interfaceName: interfaceName)
        let rate: (up: Double, down: Double)

        if let sample, let previousNetworkSample {
            let elapsed = max(sample.timestamp - previousNetworkSample.timestamp, 1)
            let sentDelta = sample.sentBytes >= previousNetworkSample.sentBytes ? sample.sentBytes - previousNetworkSample.sentBytes : 0
            let receivedDelta = sample.receivedBytes >= previousNetworkSample.receivedBytes ? sample.receivedBytes - previousNetworkSample.receivedBytes : 0
            rate = (Double(sentDelta) / elapsed, Double(receivedDelta) / elapsed)
        } else {
            rate = (0, 0)
        }

        if let sample {
            previousNetworkSample = sample
        }

        return (
            name: interface?.ssid() ?? "未连接",
            band: wifiBandText(interface: interface) ?? interfaceName,
            uploadRateBytesPerSecond: rate.up,
            downloadRateBytesPerSecond: rate.down
        )
    }

    private func readBatteryStatus() -> IslandContent.SystemStatus.Battery {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return .init(levelPercent: nil, levelText: "AC", statusText: "无内置电池", timeRemainingText: "外接电源", isCharging: false)
        }

        let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue ?? 0
        let maxCapacity = Swift.max((description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue ?? 1, 1)
        let percent = min(Swift.max(current / maxCapacity * 100, 0), 100)
        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
        let timeToEmpty = (description[kIOPSTimeToEmptyKey as String] as? NSNumber)?.intValue ?? -1
        let timeToFull = (description[kIOPSTimeToFullChargeKey as String] as? NSNumber)?.intValue ?? -1

        let statusText: String
        let remainingText: String
        if isCharging {
            statusText = "充电中"
            remainingText = timeToFull >= 0 ? durationText(minutes: timeToFull) : "等待充满"
        } else if powerSourceState == kIOPSACPowerValue {
            statusText = "已接电源"
            remainingText = "外接电源"
        } else {
            statusText = "剩余"
            remainingText = timeToEmpty >= 0 ? durationText(minutes: timeToEmpty) : "无法估算"
        }

        return .init(
            levelPercent: percent,
            levelText: percentText(percent),
            statusText: statusText,
            timeRemainingText: remainingText,
            isCharging: isCharging
        )
    }

    private func readNetworkSample(interfaceName: String) -> NetworkSample? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let start = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = start
        while let node = current {
            let interface = node.pointee
            let name = String(cString: interface.ifa_name)
            if name == interfaceName,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                return NetworkSample(
                    receivedBytes: UInt64(data.pointee.ifi_ibytes),
                    sentBytes: UInt64(data.pointee.ifi_obytes),
                    timestamp: Date().timeIntervalSince1970
                )
            }
            current = interface.ifa_next
        }

        return nil
    }

    private func appendHistory(_ value: Double, to history: [Double], maxCount: Int = 11) -> [Double] {
        let next = history + [value]
        return Array(next.suffix(maxCount))
    }

    private func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func byteText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private func durationText(minutes: Int) -> String {
        guard minutes >= 0 else { return "无法估算" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 {
            return "\(remainingMinutes) 分钟"
        }
        return "\(hours) 小时 \(remainingMinutes) 分"
    }

    private func operatingSystemName() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    private func hardwareModelIdentifier() -> String {
        sysctlString(named: "hw.model") ?? "Mac"
    }

    private func chipName() -> String {
        if let brand = sysctlString(named: "machdep.cpu.brand_string"), !brand.isEmpty {
            return brand
        }
        return hardwareModelIdentifier()
    }

    private func wifiBandText(interface: CWInterface?) -> String? {
        guard let channel = interface?.wlanChannel()?.channelNumber else { return nil }
        switch channel {
        case 1...14:
            return "2.4 GHz"
        case 15...191:
            return "5 GHz"
        default:
            return "6 GHz"
        }
    }

    private func sysctlString(named name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
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
