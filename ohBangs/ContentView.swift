import SwiftUI

struct ContentView: View {
    @ObservedObject var islandState: IslandStateStore

    var body: some View {
        IslandView(store: islandState)
    }
}

#Preview {
    ContentView(islandState: IslandStateStore())
}
