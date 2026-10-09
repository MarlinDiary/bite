import AppIntents
import Foundation
import BiteKit

// The pages Bite's widgets show, on the phone, the Mac and the watch.

/// A page by its dot's colour, for the page a widget shows.
nonisolated enum WidgetPage: String, AppEnum {
    case yellow, orange, red, purple, blue, teal, green

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let caseDisplayRepresentations: [WidgetPage: DisplayRepresentation] = [
        .yellow: "Yellow", .orange: "Orange", .red: "Red", .purple: "Purple", .blue: "Blue", .teal: "Teal", .green: "Green",
    ]

    /// The dot, counting from 0 along the dot bar.
    var dot: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// What a widget shows in the gallery before Bite has written any page.
nonisolated enum SamplePages {
    /// The pages as Bite last wrote them for the widgets, or these, before it has.
    static func orShelf() -> [String] {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup)
            .flatMap { PageShelf(folder: $0).read() } ?? markdown
    }

    static let markdown = [
        "# Welcome to Bite\nSeven dots, seven pages for whatever you're juggling right now.\n",
        "# Groceries\n- [ ] Oat milk\n- [ ] Sourdough\n- [x] Eggs\n- [ ] Lemons\n- [ ] Coffee beans\n",
        "# This week\n1. Call the plumber\n2. Book the dentist\n3. Return the library books\n",
        "", "", "", "",
    ]
}
