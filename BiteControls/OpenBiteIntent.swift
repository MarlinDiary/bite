import AppIntents

/// What Bite's control does: opens Bite as its icon does, on the page last used. Bite has this file
/// too, as it's Bite that runs it, brought up for it.
struct OpenBiteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bite"
    static let description: IntentDescription? = IntentDescription("Opens Bite on the page last used.")
    static let supportedModes: IntentModes = .foreground
    // Shortcuts has its own Open App, and Bite's Open Page.
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
