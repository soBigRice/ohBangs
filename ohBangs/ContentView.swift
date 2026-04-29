import SwiftUI

struct ContentView: View {
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        IslandView(
            store: islandState,
            settings: settings
        )
    }
}

#Preview {
    ContentView(
        islandState: IslandStateStore(),
        settings: AppSettingsStore()
    )
}
