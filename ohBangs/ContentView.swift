import SwiftUI

struct ContentView: View {
    @ObservedObject var islandState: IslandStateStore
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var weatherStore: WeatherStore

    var body: some View {
        IslandView(
            store: islandState,
            settings: settings,
            weatherStore: weatherStore
        )
    }
}

#Preview {
    ContentView(
        islandState: IslandStateStore(),
        settings: AppSettingsStore(),
        weatherStore: WeatherStore()
    )
}
