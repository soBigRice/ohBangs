import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    struct ShortcutOption: Identifiable, Hashable, Codable {
        let id: String
        let title: String
        let symbolName: String
        let bundleIdentifier: String?
        let appPath: String?
        let isBuiltIn: Bool
    }

    static let availableShortcutOptions: [ShortcutOption] = [
        ShortcutOption(id: "calendar", title: "日历", symbolName: "calendar", bundleIdentifier: "com.apple.iCal", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "files", title: "文件", symbolName: "folder.fill", bundleIdentifier: "com.apple.finder", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "music", title: "音乐", symbolName: "music.note", bundleIdentifier: "com.apple.Music", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "notes", title: "便签", symbolName: "note.text", bundleIdentifier: "com.apple.Notes", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "weather", title: "天气", symbolName: "cloud.sun.fill", bundleIdentifier: "com.apple.weather", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "safari", title: "浏览器", symbolName: "safari.fill", bundleIdentifier: "com.apple.Safari", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "terminal", title: "终端", symbolName: "terminal", bundleIdentifier: "com.apple.Terminal", appPath: nil, isBuiltIn: true),
        ShortcutOption(id: "settings", title: "设置", symbolName: "gearshape.fill", bundleIdentifier: "com.apple.systempreferences", appPath: nil, isBuiltIn: true)
    ]

    @Published var notificationEnabled: Bool = true {
        didSet { persistSettingsIfNeeded() }
    }

    @Published var previewDuration: Double = 3.0 {
        didSet { persistSettingsIfNeeded() }
    }

    @Published var expandWidth: Double = 265.0 {
        didSet { persistSettingsIfNeeded() }
    }

    @Published var customShortcutOptions: [ShortcutOption] = [] {
        didSet {
            normalizeCustomShortcutOptionsIfNeeded()
            normalizePinnedShortcutIDsIfNeeded()
            persistSettingsIfNeeded()
        }
    }

    @Published var pinnedShortcutIDs: [String] = [] {
        didSet {
            normalizePinnedShortcutIDsIfNeeded()
            persistSettingsIfNeeded()
        }
    }

    private enum StorageKey {
        static let notificationEnabled = "notificationEnabled"
        static let previewDuration = "previewDuration"
        static let expandWidth = "expandWidth"
        static let customShortcutOptions = "customShortcutOptions"
        static let pinnedShortcutIDs = "pinnedShortcutIDs"
    }

    private let userDefaults: UserDefaults
    private var isRestoringState = true
    private var isNormalizingShortcutIDs = false
    private var isNormalizingCustomShortcuts = false

    var allShortcutOptions: [ShortcutOption] {
        Self.availableShortcutOptions + customShortcutOptions
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        notificationEnabled = userDefaults.object(forKey: StorageKey.notificationEnabled) as? Bool ?? true
        previewDuration = userDefaults.object(forKey: StorageKey.previewDuration) as? Double ?? 3.0
        expandWidth = userDefaults.object(forKey: StorageKey.expandWidth) as? Double ?? 265.0
        customShortcutOptions = Self.decodeCustomShortcuts(from: userDefaults.data(forKey: StorageKey.customShortcutOptions))
        pinnedShortcutIDs = Self.normalizedShortcutIDs(
            from: userDefaults.stringArray(forKey: StorageKey.pinnedShortcutIDs) ?? Self.availableShortcutOptions.map(\.id),
            validIDs: Set((Self.availableShortcutOptions + customShortcutOptions).map(\.id))
        )
        isRestoringState = false
    }

    private func persistSettingsIfNeeded() {
        guard !isRestoringState else { return }
        userDefaults.set(notificationEnabled, forKey: StorageKey.notificationEnabled)
        userDefaults.set(previewDuration, forKey: StorageKey.previewDuration)
        userDefaults.set(expandWidth, forKey: StorageKey.expandWidth)
        userDefaults.set(try? JSONEncoder().encode(customShortcutOptions), forKey: StorageKey.customShortcutOptions)
        userDefaults.set(pinnedShortcutIDs, forKey: StorageKey.pinnedShortcutIDs)
    }

    func isShortcutPinned(_ id: String) -> Bool {
        pinnedShortcutIDs.contains(id)
    }

    func setShortcutPinned(_ id: String, isPinned: Bool) {
        if isPinned {
            guard !pinnedShortcutIDs.contains(id) else { return }
            pinnedShortcutIDs.append(id)
        } else {
            pinnedShortcutIDs.removeAll { $0 == id }
        }
    }

    func addCustomShortcut(appURL: URL) {
        guard appURL.pathExtension.lowercased() == "app" else { return }

        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let title = appURL.deletingPathExtension().lastPathComponent
        let id = "custom:\(bundleIdentifier ?? appURL.path)"
        let shortcut = ShortcutOption(
            id: id,
            title: title,
            symbolName: "app.fill",
            bundleIdentifier: bundleIdentifier,
            appPath: appURL.path,
            isBuiltIn: false
        )

        if let existingIndex = customShortcutOptions.firstIndex(where: { $0.id == id }) {
            customShortcutOptions[existingIndex] = shortcut
        } else {
            customShortcutOptions.append(shortcut)
        }

        setShortcutPinned(id, isPinned: true)
    }

    func removeCustomShortcut(id: String) {
        customShortcutOptions.removeAll { $0.id == id }
        pinnedShortcutIDs.removeAll { $0 == id }
    }

    private func normalizePinnedShortcutIDsIfNeeded() {
        guard !isNormalizingShortcutIDs else { return }

        let normalized = Self.normalizedShortcutIDs(
            from: pinnedShortcutIDs,
            validIDs: Set(allShortcutOptions.map(\.id))
        )
        guard normalized != pinnedShortcutIDs else { return }

        isNormalizingShortcutIDs = true
        pinnedShortcutIDs = normalized
        isNormalizingShortcutIDs = false
    }

    private func normalizeCustomShortcutOptionsIfNeeded() {
        guard !isNormalizingCustomShortcuts else { return }

        let normalized = Self.normalizedCustomShortcutOptions(from: customShortcutOptions)
        guard normalized != customShortcutOptions else { return }

        isNormalizingCustomShortcuts = true
        customShortcutOptions = normalized
        isNormalizingCustomShortcuts = false
    }

    private static func normalizedShortcutIDs(from ids: [String], validIDs: Set<String>) -> [String] {
        var seenIDs = Set<String>()

        return ids.compactMap { id in
            guard validIDs.contains(id), seenIDs.insert(id).inserted else {
                return nil
            }
            return id
        }
    }

    private static func normalizedCustomShortcutOptions(from options: [ShortcutOption]) -> [ShortcutOption] {
        var seenIDs = Set<String>()

        return options.compactMap { option in
            guard !option.isBuiltIn,
                  option.appPath != nil,
                  seenIDs.insert(option.id).inserted else {
                return nil
            }
            return option
        }
    }

    private static func decodeCustomShortcuts(from data: Data?) -> [ShortcutOption] {
        guard let data,
              let decoded = try? JSONDecoder().decode([ShortcutOption].self, from: data) else {
            return []
        }

        return normalizedCustomShortcutOptions(from: decoded)
    }
}
