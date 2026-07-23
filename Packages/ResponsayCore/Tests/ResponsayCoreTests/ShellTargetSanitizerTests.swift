import Testing
@testable import ResponsayCore

/// INSERT-TERMINAL-NEWLINE-006: a dictated newline must never reach a shell as Enter.
@Suite struct ShellTargetSanitizerTests {
    @Test func detectsKnownShells() {
        #expect(ShellTargetSanitizer.isShell("com.apple.Terminal"))
        #expect(ShellTargetSanitizer.isShell("com.googlecode.iterm2"))
        #expect(!ShellTargetSanitizer.isShell("com.apple.TextEdit"))
        #expect(!ShellTargetSanitizer.isShell(nil))
    }

    @Test func convertsNewlinesAndControlCharsToSpaces() {
        #expect(ShellTargetSanitizer.sanitizeForShell("ls\nmkdir foo\n") == "ls mkdir foo")
        #expect(ShellTargetSanitizer.sanitizeForShell("echo hi\r") == "echo hi")
        #expect(ShellTargetSanitizer.sanitizeForShell("a\t\tb") == "a b")
        #expect(ShellTargetSanitizer.sanitizeForShell("rm -rf /tmp/x\n") == "rm -rf /tmp/x")
    }

    @Test func passesThroughNonShellTargetsUnchanged() {
        #expect(ShellTargetSanitizer.sanitize("line1\nline2", forTargetBundleID: "com.apple.TextEdit") == "line1\nline2")
        #expect(ShellTargetSanitizer.sanitize("ls\nrm", forTargetBundleID: "com.apple.Terminal") == "ls rm")
        #expect(ShellTargetSanitizer.sanitize("plain", forTargetBundleID: nil) == "plain")
    }
}
