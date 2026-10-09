import SwiftUI
import WatchKit
import BiteKit

/// A whole page, scrolled with the Digital Crown: a to-do ticked off, or on again, at a tap on its
/// line, and a line added at the end from the system's dictation, Scribble or keyboard, as if typed
/// there, carrying on a list the page ends with.
struct PageView: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var textSize = WatchLook.textSize

    var body: some View {
        let ink = DotPalette.colors[dot]
        // Read for the page's changes, which come in as other devices' do.
        let _ = store.revisions[dot]
        let glance = PageGlance(markdown: store.markdown[dot])
        ScrollView {
            if glance.isEmpty {
                DotStatement(title: ink.name, ink: ink, line: WatchLook.emptyLine, sizes: WatchLook.emptySizes)
                    .padding(.top, 24)
            } else {
                PageGlanceView(glance: glance, page: dot, ink: ink, metrics: WatchLook.metrics(textSize: textSize),
                               showsAll: true) { tick in
                    WKInterfaceDevice.current().play(.click)
                    store.tick(tick)
                }
                .scenePadding(.horizontal)
            }
        }
        .containerBackground(WatchLook.background(ink), for: .navigation)
        .toolbar {
            // Top right, across from the way back, the time moving to the middle for it, as in the
            // system's own apps (user, 2026-10-09).
            ToolbarItem(placement: .topBarTrailing) {
                TextFieldLink(prompt: Text("Add a Line")) {
                    Label("Add a Line", systemImage: "plus")
                } onSubmit: { text in
                    store.add(text, asToDo: false, to: dot)
                }
            }
        }
    }
}
