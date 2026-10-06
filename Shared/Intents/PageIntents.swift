import AppIntents
#if canImport(UIKit)
import UIKit
#endif

// What Bite can do for Siri and Shortcuts, and Spotlight with them: open a page, and add a to-do
// to one. The App Shortcuts below give Siri phrases for each, there as soon as Bite is, in English
// as the app is.

/// A page to open, by its dot's colour, shown with its ring, as Spotlight's results for its lines
/// are.
nonisolated enum PageToOpen: String, AppEnum {
    case yellow, orange, red, purple, blue, teal, green

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let caseDisplayRepresentations: [PageToOpen: DisplayRepresentation] = [
        .yellow: DisplayRepresentation(title: "Yellow", image: .init(named: "SpotlightRing-Yellow"), synonyms: ["Yellow page", "Yellow dot"]),
        .orange: DisplayRepresentation(title: "Orange", image: .init(named: "SpotlightRing-Orange"), synonyms: ["Orange page", "Orange dot"]),
        .red: DisplayRepresentation(title: "Red", image: .init(named: "SpotlightRing-Red"), synonyms: ["Red page", "Red dot"]),
        .purple: DisplayRepresentation(title: "Purple", image: .init(named: "SpotlightRing-Purple"), synonyms: ["Purple page", "Purple dot"]),
        .blue: DisplayRepresentation(title: "Blue", image: .init(named: "SpotlightRing-Blue"), synonyms: ["Blue page", "Blue dot"]),
        .teal: DisplayRepresentation(title: "Teal", image: .init(named: "SpotlightRing-Teal"), synonyms: ["Teal page", "Teal dot"]),
        .green: DisplayRepresentation(title: "Green", image: .init(named: "SpotlightRing-Green"), synonyms: ["Green page", "Green dot"]),
    ]

    /// The dot, counting from 0 along the dot bar.
    var dot: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// A page to add a to-do to, by its dot's colour, shown with a tick made as its ring is. A type of
/// its own: Spotlight and Shortcuts show a page's shortcut by the page's picture alone, and with
/// the ring on both, adding looked like opening.
nonisolated enum PageForToDo: String, AppEnum {
    case yellow, orange, red, purple, blue, teal, green

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let caseDisplayRepresentations: [PageForToDo: DisplayRepresentation] = [
        .yellow: DisplayRepresentation(title: "Yellow", image: .init(named: "ToDoCheck-Yellow"), synonyms: ["Yellow page", "Yellow dot"]),
        .orange: DisplayRepresentation(title: "Orange", image: .init(named: "ToDoCheck-Orange"), synonyms: ["Orange page", "Orange dot"]),
        .red: DisplayRepresentation(title: "Red", image: .init(named: "ToDoCheck-Red"), synonyms: ["Red page", "Red dot"]),
        .purple: DisplayRepresentation(title: "Purple", image: .init(named: "ToDoCheck-Purple"), synonyms: ["Purple page", "Purple dot"]),
        .blue: DisplayRepresentation(title: "Blue", image: .init(named: "ToDoCheck-Blue"), synonyms: ["Blue page", "Blue dot"]),
        .teal: DisplayRepresentation(title: "Teal", image: .init(named: "ToDoCheck-Teal"), synonyms: ["Teal page", "Teal dot"]),
        .green: DisplayRepresentation(title: "Green", image: .init(named: "ToDoCheck-Green"), synonyms: ["Green page", "Green dot"]),
    ]

    var dot: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// Adds a to-do to the end of a page, as if typed there (see `PageAddition`).
struct AddToDoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add To-Do"
    static let description: IntentDescription? = IntentDescription(
        "Adds a to-do to the end of a page. Each line of the text is a to-do of its own.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "To-Do", requestValueDialog: "What's the to-do?")
    var text: String

    @Parameter(title: "Page", description: "The page last used in Bite, if none is picked.")
    var page: PageForToDo?

    @Dependency private var store: DotStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add to-do \(\.$text) to \(\.$page)")
    }

    /// Done without a word: a card saying so, after the to-do was typed, was one more tap.
    @MainActor
    func perform() async throws -> some IntentResult {
        PageIntents.add(text, to: page, in: store)
        PageIntents.sendIfOffScreen()
        return .result()
    }
}

/// Opens Bite on a page: on the phone Bite comes up, on the Mac the panel.
struct OpenPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Page"
    static let description: IntentDescription? = IntentDescription("Opens Bite on a page.")
    #if os(macOS)
    // The panel comes up over whatever is in use, as from the ring, with no app brought forward.
    static let supportedModes: IntentModes = .background
    #else
    static let supportedModes: IntentModes = .foreground
    #endif

    @Parameter(title: "Page", requestValueDialog: "Which page?")
    var page: PageToOpen

    @Dependency private var store: DotStore

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$page)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        store.open(dot: page.dot)
        return .result()
    }
}

struct BiteShortcuts: AppShortcutsProvider {
    /// The orange of Bite's icon, where the system doesn't use its own blue.
    static let shortcutTileColor: ShortcutTileColor = .tangerine

    // Open first: Spotlight's top hits for Bite are the first one's, a ring for each page. Each is
    // also shown a page at a time, which Shortcuts lists under the name given here.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPageIntent(), phrases: [
            "Open \(\.$page) in \(.applicationName)",
            "Open the \(\.$page) page in \(.applicationName)",
            "Show \(\.$page) in \(.applicationName)",
        ], shortTitle: "Open Page", systemImageName: "circle", parameterPresentation: ParameterPresentation(
            for: \.$page, summary: Summary("Open \(\.$page)"), optionsCollections: {
                OptionsCollection(PagesToOpen(), title: "Open Page", systemImageName: "circle")
            }))
        AppShortcut(intent: AddToDoIntent(), phrases: [
            "Add to \(.applicationName)",
            "Add a to-do to \(.applicationName)",
            "Add a task to \(.applicationName)",
            "Add to \(\.$page) in \(.applicationName)",
            "Add to the \(\.$page) page in \(.applicationName)",
            "Add a to-do to \(\.$page) in \(.applicationName)",
            "Add a to-do to the \(\.$page) page in \(.applicationName)",
        ], shortTitle: "Add To-Do", systemImageName: "checkmark", parameterPresentation: ParameterPresentation(
            for: \.$page, summary: Summary("Add a to-do to \(\.$page)"), optionsCollections: {
                OptionsCollection(PagesForToDos(), title: "Add To-Do", systemImageName: "checkmark")
            }))
    }
}

/// Every page, in the dot bar's order, for the shortcuts shown a page at a time.
nonisolated struct PagesToOpen: DynamicOptionsProvider {
    func results() async throws -> [PageToOpen] {
        PageToOpen.allCases
    }
}

nonisolated struct PagesForToDos: DynamicOptionsProvider {
    func results() async throws -> [PageForToDo] {
        PageForToDo.allCases
    }
}

/// What the intents do, given a store, which tests give one of their own.
enum PageIntents {
    /// Adds `text` to `page`, or the page last used, as a to-do: which page that was, and whether
    /// there was anything to add.
    @discardableResult
    static func add(_ text: String, to page: PageForToDo?, in store: DotStore) -> (dot: Int, added: Bool) {
        let dot = page?.dot ?? store.selection
        return (dot, store.add(text, asToDo: true, to: dot))
    }

    /// Run while Bite is off screen, as for Siri, the phone may stop Bite right after: what
    /// changed goes up to iCloud now. The Mac's Bite carries on.
    static func sendIfOffScreen() {
        #if canImport(UIKit)
        if UIApplication.shared.applicationState != .active { PageSync.shared?.sendBeforeLeaving() }
        #endif
    }
}
