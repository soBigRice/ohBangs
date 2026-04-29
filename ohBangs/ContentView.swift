import SwiftUI

struct ContentView: View {
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var settings: AppSettingsStore
    let openSettingsPanel: () -> Void

    var body: some View {
        IslandView(
            store: islandState,
            settings: settings,
            openSettingsPanel: openSettingsPanel
        )
    }
}

#Preview {
    ContentView(
        islandState: IslandStateStore(),
        settings: AppSettingsStore(),
        openSettingsPanel: {}
    )
}
