import Foundation
import Testing
@testable import ResponsayCore

@Test func modeResolver_resolvesFastInputModes() {
    let raw = CaptureModeResolver.resolve(.raw)
    #expect(raw.transformKind == .none)
    #expect(raw.outputLanguage == .source)
    #expect(raw.sidecarPolicy == .collapsed)
    #expect(raw.insertPolicy == .insertImmediately)

    let polish = CaptureModeResolver.resolve(.polishSameLanguage)
    #expect(polish.transformKind == .sameLanguagePolish)
    #expect(polish.outputLanguage == .source)
    #expect(polish.sidecarPolicy == .badgeOnly)
    #expect(polish.insertPolicy == .insertImmediately)

    let intentAware = CaptureModeResolver.resolve(.intentAwareDictation)
    #expect(intentAware.transformKind == .intentCompilation)
    #expect(intentAware.outputLanguage == .source)
    #expect(intentAware.sidecarPolicy == .badgeOnly)
    #expect(intentAware.insertPolicy == .insertImmediately)
}

@Test func modeResolver_resolvesLearningModes() {
    let english = CaptureModeResolver.resolve(.expressInEnglish)
    #expect(english.transformKind == .intentToEnglish)
    #expect(english.outputLanguage == .english)
    #expect(english.sidecarPolicy == .autoOpenCoach)
    #expect(english.insertPolicy == .insertImmediately)

    let coach = CaptureModeResolver.resolve(.coach)
    #expect(coach.transformKind == .coachOnly)
    #expect(coach.sidecarPolicy == .autoOpenCoach)
    #expect(coach.insertPolicy == .noInsert)
}

@Test func modeResolver_resolvesSelectionModes() {
    let rewrite = CaptureModeResolver.resolve(.rewriteSelection)
    #expect(rewrite.transformKind == .rewriteSelection)
    #expect(rewrite.outputLanguage == .english)
    #expect(rewrite.sidecarPolicy == .badgeOnly)
    #expect(rewrite.insertPolicy == .replaceSelection)

    let translate = CaptureModeResolver.resolve(.translateSelection)
    #expect(translate.transformKind == .translateSelection)
    #expect(translate.outputLanguage == .target)
    #expect(translate.sidecarPolicy == .collapsed)
    #expect(translate.insertPolicy == .replaceSelection)
}

@Test func modeResolver_resolvesLegalPaletteAsNoInsert() {
    let legal = CaptureModeResolver.resolve(.legal)
    #expect(legal.transformKind == .legalSkillPalette)
    #expect(legal.outputLanguage == .source)
    #expect(legal.sidecarPolicy == .none)
    #expect(legal.insertPolicy == .noInsert)   // selecting a card runs a skill, never inserts
}

@Test func modeResolver_appliesSidecarOverrideWithoutChangingInsertPolicy() {
    let resolved = CaptureModeResolver.resolve(.expressInEnglish, sidecarOverride: .highlight)
    #expect(resolved.sidecarPolicy == .highlight)
    #expect(resolved.insertPolicy == .insertImmediately)
    #expect(resolved.transformKind == .intentToEnglish)
}
