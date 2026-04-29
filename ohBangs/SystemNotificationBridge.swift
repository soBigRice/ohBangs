import Foundation
import UserNotifications

@MainActor
final class SystemNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
    static let triggerTestNotification = Notification.Name("IslandTriggerTestNotification")

    var onNotification: ((String, String) -> Void)?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "系统通知"
        content.body = "你收到了一条新消息"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let title = notification.request.content.title
        let subtitle = notification.request.content.body
        Task { @MainActor [weak self] in
            self?.onNotification?(title.isEmpty ? "通知" : title, subtitle.isEmpty ? "你收到了一条新消息" : subtitle)
        }
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let title = response.notification.request.content.title
        let subtitle = response.notification.request.content.body
        Task { @MainActor [weak self] in
            self?.onNotification?(title.isEmpty ? "通知" : title, subtitle.isEmpty ? "你收到了一条新消息" : subtitle)
        }
        completionHandler()
    }
}
