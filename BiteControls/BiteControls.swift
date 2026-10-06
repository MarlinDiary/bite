import AppIntents
import SwiftUI
import WidgetKit

/// Bite's widgets, a page, the pages turned in place, and the to-dos from every page, on the Home
/// Screen, the Lock Screen or the Mac's desktop, and on the phone its control, for Control Center,
/// the Lock Screen and the Action button. The Mac's Bite is in the menu bar already.
@main
struct BiteControlBundle: WidgetBundle {
    var body: some Widget {
        SinglePageWidget()
        PageWidget()
        ToDosWidget()
        #if os(iOS)
        OpenBiteControl()
        #endif
    }
}

#if os(iOS)

/// Bite's ring, opening Bite. The system's own Open App can open Bite too, but shows its icon,
/// shrunk into the control.
///
/// Control Center scales a control's symbol until the circle round its ink is about 41 pt across,
/// however big it's drawn, where its own circles (Screen Recording's, Dark Mode's) are 34. The
/// ring's symbol has four specks too small to see, 1.2 ring radii out, so that circle is theirs and
/// the ring comes out 34 across, its band the icon's share of that.
struct OpenBiteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.chenyeni.bite.open") {
            ControlWidgetButton(action: OpenBiteIntent()) {
                Label("Bite", image: "bite.ring")
            }
        }
        .displayName("Bite")
        .description("Opens Bite on the page last used.")
    }
}
#endif
