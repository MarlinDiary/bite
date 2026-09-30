import SwiftUI

@main
struct BiteApp: App {
    @State private var store = DotStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
