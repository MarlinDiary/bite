#if !canImport(UIKit)
import Testing
@testable import Bite

/// Settings copies the one command that lets Terminal find `bite` by its name.
struct CommandLineToolTests {
    @Test func theCommandLinksTheToolInThisBite() {
        #expect(CommandLineTool.path.hasSuffix(".app/Contents/Helpers/bite"))
        #expect(CommandLineTool.installCommand(tool: "/Applications/Bite.app/Contents/Helpers/bite")
            == "sudo mkdir -p /usr/local/bin && sudo ln -sf /Applications/Bite.app/Contents/Helpers/bite /usr/local/bin/bite")
    }

    /// A Bite somewhere with spaces in its path is still one word to the shell.
    @Test func aPathWithSpacesIsQuoted() {
        #expect(CommandLineTool.quoted("/Users/sam/My Apps/bite") == "'/Users/sam/My Apps/bite'")
        #expect(CommandLineTool.quoted("/Users/sam's/bite") == #"'/Users/sam'\''s/bite'"#)
    }
}
#endif
