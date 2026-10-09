import BiteKit

/// What the first four dots hold on first launch, so there's something to look at.
enum SampleContent {
    static func markdown(for dot: Int) -> String {
        #if os(macOS)
        markdown(for: dot, onMac: true)
        #elseif os(watchOS)
        // The watch's pages come from iCloud, the person's own, a moment after it first opens: its
        // own samples would only show until then, telling of dots up top and swipes it hasn't got.
        ""
        #else
        markdown(for: dot, onMac: false)
        #endif
    }

    /// Whether `markdown` is a dot's first-launch page as it came, on a phone or on a Mac.
    static func isUntouched(_ markdown: String, dot: Int) -> Bool {
        let page = normalized(markdown)
        return [true, false].contains { onMac in
            let sample = Self.markdown(for: dot, onMac: onMac)
            return !sample.isEmpty && normalized(sample) == page
        }
    }

    private static func normalized(_ markdown: String) -> String {
        MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown))
    }

    private static func markdown(for dot: Int, onMac: Bool) -> String {
        switch dot {
        case 0: welcome(onMac: onMac)
        case 1: groceries
        case 2: planning
        case 3: snippets
        default: ""
        }
    }

    private static func welcome(onMac: Bool) -> String {
        let switching = onMac ? "Click a dot up top, or press ⌘1 to ⌘7, to switch." : "Swipe, or tap a dot up top to switch."
        let ticking = onMac ? "Click a checkbox to tick it off" : "Tap a checkbox to tick it off"
        return """
    # Welcome to Bite
    Seven dots, seven pages for whatever you're juggling right now. \(switching)
    ## Markdown shortcuts, Notion style
    - Type `#` and a space at the start of a line for a heading
    - `-` and a space for a list, `1.` and a space for a numbered list
    - `[]` for a to-do
    - `>` and a space for a quote
    - `---` for a divider, three backticks for a code block
    - Wrap text in `**` for **bold**, `*` for *italic*, `~~` for ~~strikethrough~~, backticks for `code`
    - \(ticking)

    > Everything is saved as Markdown, and copies out as Markdown too.

    """
    }

    private static let groceries = """
    # Weekend groceries
    - [ ] Milk
    - [ ] Eggs
    - [x] Coffee beans
    - [ ] Cat food
    - [ ] Laundry detergent

    """

    private static let planning = """
    ## Planning, Sept 29
    1. Build the iPhone prototype first
    2. The editor is the core
        - Input rules live in **BiteKit**
        - The UI is a thin shell
    3. The Mac menu bar app comes next
    ---
    **Next**: try it out, then decide the details.

    """

    private static let snippets = """
    ## Handy commands
    ```
    xcodebuild -scheme Bite build
    swift test
    ```
    ~~The old build script~~ isn't needed anymore.

    """
}
