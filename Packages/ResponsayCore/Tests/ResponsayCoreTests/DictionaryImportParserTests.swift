import Testing
@testable import ResponsayCore

struct DictionaryImportParserTests {
    @Test func txt_oneTermPerLine_allNew() {
        let plan = DictionaryImportParser.parse("阿尔法\nBeta\n伽马", format: .txt, existing: [])
        #expect(plan.additions == ["阿尔法", "Beta", "伽马"])
        #expect(plan.duplicates.isEmpty)
        #expect(plan.invalid.isEmpty)
    }

    @Test func trimsWhitespaceAndSkipsBlankLines() {
        let plan = DictionaryImportParser.parse("  阿尔法  \n\n   \nBeta\n", format: .txt, existing: [])
        #expect(plan.additions == ["阿尔法", "Beta"])
        #expect(plan.invalid.isEmpty) // blank/whitespace lines are formatting, dropped silently
    }

    @Test func dedupsAgainstExistingDictionary() {
        let plan = DictionaryImportParser.parse("阿尔法\nBeta", format: .txt, existing: ["Beta"])
        #expect(plan.additions == ["阿尔法"])
        #expect(plan.duplicates == ["Beta"])
    }

    @Test func dedupsWithinBatch_firstWins() {
        let plan = DictionaryImportParser.parse("阿尔法\n阿尔法\nBeta", format: .txt, existing: [])
        #expect(plan.additions == ["阿尔法", "Beta"])
        #expect(plan.duplicates == ["阿尔法"])
    }

    @Test func rejectsTooLongTerms_ratherThanTruncating() {
        let plan = DictionaryImportParser.parse("abc\nabcd", format: .txt, existing: [], maxLength: 3)
        #expect(plan.additions == ["abc"])
        #expect(plan.invalid == ["abcd"])
        #expect(plan.duplicates.isEmpty)
    }

    @Test func csv_takesFirstColumn() {
        let plan = DictionaryImportParser.parse("阿尔法,名词,note\nBeta,adj", format: .csv, existing: [])
        #expect(plan.additions == ["阿尔法", "Beta"])
    }

    @Test func csv_handlesCrlfLineEndings() {
        let plan = DictionaryImportParser.parse("阿尔法,x\r\nBeta,y\r\n", format: .csv, existing: [])
        #expect(plan.additions == ["阿尔法", "Beta"])
    }

    @Test func emptyFile_yieldsEmptyPlan() {
        let plan = DictionaryImportParser.parse("", format: .txt, existing: [])
        #expect(plan.additions.isEmpty)
        #expect(plan.duplicates.isEmpty)
        #expect(plan.invalid.isEmpty)
        #expect(plan.addCount == 0)
    }

    @Test func allDuplicates_yieldsNoAdditions() {
        let plan = DictionaryImportParser.parse("Alpha\nBeta", format: .txt, existing: ["Alpha", "Beta"])
        #expect(plan.additions.isEmpty)
        #expect(plan.duplicates == ["Alpha", "Beta"])
    }

    @Test func mixedDirtyData_partitionsCorrectly() {
        // existing: Gamma; batch has: new, dup-vs-existing, intra-batch dup, blank, too-long, csv-tail
        let contents = "阿尔法,词性\nGamma\n阿尔法\n\ntoolongterm\nBeta"
        let plan = DictionaryImportParser.parse(contents, format: .csv, existing: ["Gamma"], maxLength: 6)
        #expect(plan.additions == ["阿尔法", "Beta"])
        #expect(plan.duplicates == ["Gamma", "阿尔法"])
        #expect(plan.invalid == ["toolongterm"])
    }
}
