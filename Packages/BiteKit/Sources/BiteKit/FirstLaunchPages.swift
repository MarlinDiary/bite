/// The pages Bite opens with the first time, one to a dot: a welcome, a list to tick off, a plan,
/// and the Markdown shortcuts, so there's something to look at, and the first dots have their
/// colours. The rest are empty, to start on. The widgets show them too, before Bite has written
/// any page, so the gallery shows what Bite opens with (user, 2026-10-09).
///
/// They're written alike for every device: a page goes to the person's others through iCloud, and
/// a word for one device, a tap or a click, turned up on all of them. Each starts with a heading,
/// which names the page wherever a page is named: in widgets, Spotlight and Apple Vision Pro's
/// column of tabs.
public enum FirstLaunchPages {
    public static let markdown = [welcome, groceries, thisWeek, formatting, "", "", ""]

    static let welcome = """
    # Welcome to Bite
    Seven dots, seven pages for whatever you're juggling right now.
    - A dot shows its colour once its page has something on it
    - Pages save as you type, and reach your other devices through iCloud
    - Done with a page? Clear it from the … menu

    """

    static let groceries = """
    # Groceries
    - [ ] Oat milk
    - [ ] Sourdough
    - [x] Eggs
    - [ ] Lemons
    - [ ] Coffee beans

    > Tick them off here, or on a widget. To add one from anywhere, say “Add to Bite” to Siri.

    """

    static let thisWeek = """
    # This week
    1. Call the plumber
    2. Book the dentist
    3. Return the library books
    ---
    **Saturday:** brunch with Mia, 11 am

    """

    static let formatting = """
    # Formatting
    Type these at the start of a line:
    - `#` and a space for a heading
    - `-` and a space for a list, `1.` and a space for a numbered list
    - `[]` for a to-do
    - `>` and a space for a quote
    - `---` for a divider, three backticks for a code block

    Wrap words in `**` for **bold**, `*` for *italic*, `~~` for ~~strikethrough~~, or backticks for `code`, and `[text](address)` makes a link. Or select them and pick a style.

    > Everything is plain Markdown underneath, and copies out as Markdown too.

    """
}
