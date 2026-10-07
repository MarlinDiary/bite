import SwiftUI
import BiteKit

struct RootView: View {
    @Environment(DotStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PagesView(leading: { _ in EmptyView() }, trailing: { DotMenu(dot: $0) })
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.saveNow() }
            }
    }
}
