import AppIntents
import SwiftUI
import WidgetKit

/// Bite's controls, for Control Center, the Lock Screen and the Action button.
@main
struct BiteControlBundle: WidgetBundle {
    var body: some Widget {
        OpenBiteControl()
    }
}

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
