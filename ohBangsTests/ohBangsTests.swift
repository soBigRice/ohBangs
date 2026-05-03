//
//  ohBangsTests.swift
//  ohBangsTests
//
//  Created by 伟（Wade） 王 on 2026/4/27.
//

import Testing
@testable import ohBangs

struct ohBangsTests {
    @MainActor
    @Test func persistsScalarSettings() {
        let suiteName = "ohBangsTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let initialSettings = AppSettingsStore(userDefaults: defaults)
        initialSettings.notificationEnabled = false
        initialSettings.previewDuration = 6
        initialSettings.expandWidth = 300

        let restoredSettings = AppSettingsStore(userDefaults: defaults)
        #expect(restoredSettings.notificationEnabled == false)
        #expect(restoredSettings.previewDuration == 6)
        #expect(restoredSettings.expandWidth == 300)
    }
}
