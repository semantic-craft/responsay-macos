import Testing
@testable import ResponsayCore

@Suite("RelaunchCommand — self-relaunch shell command")
struct RelaunchCommandTests {
    @Test func buildsShWaitForPidThenOpen() {
        let cmd = RelaunchCommand.shell(pid: 1234, bundlePath: "/Applications/Responsay.app")
        #expect(cmd[0] == "/bin/sh")
        #expect(cmd[1] == "-c")
        #expect(cmd[2] == "while kill -0 1234 2>/dev/null; do sleep 0.2; done; /usr/bin/open '/Applications/Responsay.app'")
    }

    @Test func quotesPathWithSpaces() {
        let cmd = RelaunchCommand.shell(pid: 1, bundlePath: "/My Apps/Responsay.app")
        #expect(cmd[2].contains("/usr/bin/open '/My Apps/Responsay.app'"))
    }

    @Test func escapesEmbeddedSingleQuote_soPathCannotBreakOut() {
        let cmd = RelaunchCommand.shell(pid: 1, bundlePath: "/U/o'brien/R.app")
        #expect(cmd[2].contains("'/U/o'\\''brien/R.app'"))   // the '\'' idiom
        #expect(!cmd[2].contains("open '/U/o'brien"))         // raw quote never survives unescaped
    }

    @Test func singleQuoted_wrapsAndEscapes() {
        #expect(RelaunchCommand.singleQuoted("abc") == "'abc'")
        #expect(RelaunchCommand.singleQuoted("a'b") == "'a'\\''b'")
    }
}
