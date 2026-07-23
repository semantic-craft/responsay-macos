import Testing
import Foundation
@testable import ResponsayCore

@Test func compose_bothEmpty_returnsNil() {
    #expect(StyleHintComposer.compose(register: nil, personalStyle: nil) == nil)
    #expect(StyleHintComposer.compose(register: "  ", personalStyle: "  ") == nil)
}

@Test func compose_registerOnly_passesThrough() {
    #expect(StyleHintComposer.compose(register: "REG", personalStyle: "  ") == "REG")
}

@Test func compose_styleOnly_wrapsWithRedLineCaveat() {
    let out = StyleHintComposer.compose(register: nil, personalStyle: "偏简洁")
    #expect(out?.contains("偏简洁") == true)
    #expect(out?.contains("服从上方红线") == true)   // style only nudges 措辞, never overrides faithfulness
}

@Test func compose_both_registerBeforeStyle() {
    let out = try! #require(StyleHintComposer.compose(register: "REG", personalStyle: "偏简洁"))
    let reg = try! #require(out.range(of: "REG"))
    let style = try! #require(out.range(of: "偏简洁"))
    #expect(reg.lowerBound < style.lowerBound)
}
