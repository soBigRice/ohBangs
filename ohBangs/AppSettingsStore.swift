import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var notificationEnabled: Bool = true
    @Published var previewDuration: Double = 3.0
    @Published var expandWidth: Double = 265.0
}
