/// What the first four dots hold on first launch, so there's something to look at.
enum SampleContent {
    static func markdown(for dot: Int) -> String {
        switch dot {
        case 0: welcome
        case 1: groceries
        case 2: planning
        case 3: snippets
        default: ""
        }
    }

    #if os(macOS)
    private static let switching = "Click a dot up top, or press ⌘1 to ⌘7, to switch."
    private static let ticking = "Click a checkbox to tick it off"
    #else
    private static let switching = "Swipe, or tap a dot up top to switch."
    private static let ticking = "Tap a checkbox to tick it off"
    #endif

    private static let welcome = """
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
