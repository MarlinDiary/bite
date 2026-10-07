import Foundation

/// A page sent in Messages: a card of it as it was when sent, which anyone sees, and the page itself
/// in the message's address, which Bite in Messages reads it from when the card is tapped. Neither
/// changes after: it's the page as it was, for someone to read.
public struct PageCard: Equatable, Sendable {
    /// The page, counting from 0 along the dot bar, whose colour the card is.
    public let page: Int
    public let markdown: String
    /// Whether the end of the page was left out, for the message to hold it.
    public var isCut: Bool

    /// The most of a page a message's address holds, packed and written out, in characters.
    public static let room = 4_000

    public init(page: Int, markdown: String, isCut: Bool = false) {
        self.page = page
        self.markdown = markdown
        self.isCut = isCut
    }

    /// The page's first line with words on it, as words: what Messages says the message is. With
    /// none, the page's colour.
    public var title: String {
        PageGlance(markdown: markdown).title ?? DotPalette.colors[page].name
    }

    /// The heading the page starts with, which goes in the bar under the card rather than on it.
    public var heading: String? {
        PageGlance(markdown: markdown).heading
    }

    /// The page in an address of query items alone, as Messages keeps a message's data: Bite's mark,
    /// the page's dot, and its Markdown packed. A page too long for a message loses lines from its end
    /// until it fits, and says so. An address of a scheme of Bite's own came back with no message.
    public var url: URL? {
        var lines = markdown.components(separatedBy: "\n")
        var isCut = isCut
        while true {
            if let url = Self.url(page: page, markdown: lines.joined(separator: "\n"), isCut: isCut),
               url.absoluteString.count <= Self.room {
                return url
            }
            guard lines.count > 1 else { return nil }
            lines.removeLast(max(1, lines.count / 8))
            isCut = true
        }
    }

    private static func url(page: Int, markdown: String, isCut: Bool) -> URL? {
        guard let packed = try? (Data(markdown.utf8) as NSData).compressed(using: .zlib) as Data else { return nil }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "bite", value: "page"),
            URLQueryItem(name: "dot", value: String(page)),
            URLQueryItem(name: "text", value: packed.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")),
        ] + (isCut ? [URLQueryItem(name: "cut", value: "1")] : [])
        return components.url
    }

    /// A card sent from Bite, read back from its message's address.
    public init?(url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(URLQueryItem(name: "bite", value: "page")),
              let dot = items.first(where: { $0.name == "dot" })?.value.flatMap(Int.init), DotPalette.colors.indices.contains(dot),
              var text = items.first(where: { $0.name == "text" })?.value else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let packed = Data(base64Encoded: text),
              let data = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let markdown = String(data: data, encoding: .utf8) else { return nil }
        self.init(page: dot, markdown: markdown, isCut: items.contains { $0.name == "cut" })
    }
}
