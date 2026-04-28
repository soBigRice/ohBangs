import Foundation

struct IslandContent: Sendable {
    let appName: String
    let title: String
    let subtitle: String
    let isLive: Bool
}

protocol IslandContentProvider: AnyObject {
    func start(onUpdate: @escaping (IslandContent) -> Void)
    func stop()
}

final class MockIslandContentProvider: IslandContentProvider {
    private var timerTask: Task<Void, Never>?
    private let messages: [IslandContent] = [
        IslandContent(appName: "ohBangs", title: "番茄钟进行中", subtitle: "剩余 24:59", isLive: true),
        IslandContent(appName: "ohBangs", title: "同步任务中", subtitle: "iCloud Drive", isLive: true),
        IslandContent(appName: "ohBangs", title: "收到新消息", subtitle: "来自开发助手", isLive: false)
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
