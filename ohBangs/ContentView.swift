import SwiftUI

struct ContentView: View {
    @ObservedObject var islandState: IslandStateStore

    var body: some View {
        IslandView(store: islandState)
            .background(Color.clear)
    }
}

#Preview {
    ContentView(islandState: IslandStateStore())
}
