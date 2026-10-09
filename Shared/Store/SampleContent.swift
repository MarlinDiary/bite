import BiteKit

/// What the dots hold on first launch: Bite's first pages (see `FirstLaunchPages`), but on the
/// watch.
enum SampleContent {
    static func markdown(for dot: Int) -> String {
        #if os(watchOS)
        // The watch's pages come from iCloud, the person's own, a moment after it first opens: its
        // own samples would only show until then.
        ""
        #else
        FirstLaunchPages.markdown.indices.contains(dot) ? FirstLaunchPages.markdown[dot] : ""
        #endif
    }

    /// Whether `markdown` is a dot's first-launch page as it came.
    static func isUntouched(_ markdown: String, dot: Int) -> Bool {
        guard FirstLaunchPages.markdown.indices.contains(dot) else { return false }
        let sample = FirstLaunchPages.markdown[dot]
        return !sample.isEmpty && normalized(sample) == normalized(markdown)
    }

    private static func normalized(_ markdown: String) -> String {
        MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown))
    }
}
