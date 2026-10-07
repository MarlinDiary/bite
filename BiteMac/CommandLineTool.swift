import Foundation

/// Bite's `bite` tool, which comes in Bite.app, and the command that lets Terminal find it by its
/// name, for the person or an AI working there.
enum CommandLineTool {
    /// The one in this Bite.
    static var path: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/bite").path(percentEncoded: false)
    }

    /// Puts a link to the tool where Terminal looks for commands. Bite can't itself: an app on the
    /// App Store keeps to its own folders.
    static func installCommand(tool: String = path) -> String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf \(quoted(tool)) /usr/local/bin/bite"
    }

    /// A path as the shell takes it: in quotes when it has anything but letters, digits and
    /// / . _ - in it.
    static func quoted(_ path: String) -> String {
        let plain = path.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-".contains($0)) }
        return plain ? path : "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
