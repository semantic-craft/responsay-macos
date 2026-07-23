import Foundation

struct DemoFrameState: Equatable, Sendable {
    enum PillMode: Equatable, Sendable { case listening, thinking }

    var selectScale = 0.0
    var flashOpacity = 0.0

    var hotkeyText = ""
    var hotkeyOpacity = 0.0
    var hotkeyOffsetY = 0.0
    var hotkeyScale = 1.0

    var pillMode = PillMode.thinking
    var pillLabel = ""
    var pillOpacity = 0.0
    var pillOffsetY = 0.0
    var pillScale = 1.0
    var pillTime = ""

    var panelOpacity = 0.0
    var panelOffsetY = 0.0
    var panelPrimaryActive = false

    var wordCount = 0
    var contentReplaced = false
    var waveActive = false

    // Legal demo extensions
    var anchorRevealCount = 0
    var anchorFlashIndex = -1
    var searchPageOpacity = 0.0
    var searchFocusIndex = -1
    var matchRevealCount = 0
    var verifiedSourceRevealCount = 0
    var keywordRevealCount = 0
    var queryOpacity = 0.0
    var urlRevealCount = 0

    // 划词菜单 popup (verify) + 截图识别 marquee
    var menuOpacity = 0.0
    var menuHighlight = false   // 来源核验 row pulse
    var marqueeScale = 0.0      // snap OCR drag-select reveal
}

enum DemoTimeline {

    // MARK: - Easing helpers

    static func clamp(_ n: Double) -> Double { max(0, min(1, n)) }
    static func p(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    static func easeOut(_ n: Double) -> Double { 1 - pow(1 - clamp(n), 3) }

    static func easeInOut(_ n: Double) -> Double {
        let n = clamp(n)
        return n < 0.5 ? 4 * n * n * n : 1 - pow(-2 * n + 2, 3) / 2
    }

    static func lerp(_ a: Double, _ b: Double, _ n: Double) -> Double { a + (b - a) * n }

    static func windowed(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        min(easeOut(p(t, a, b)), 1 - easeOut(p(t, c, d)))
    }

    static func mmss(_ ms: Double) -> String { String(format: "00:%02d", max(0, Int(ms / 1000))) }

    // MARK: - Dispatch

    static func state(for kind: FeatureDemoKind, at t: Double, script: FeatureDemoScript) -> DemoFrameState {
        switch kind {
        case .coach:           coach(t, script)
        case .dictate:         dictate(t, script)
        case .translate:       translate(t, script)
        case .english:         english(t, script)
        case .selectTranslate: selectTranslate(t, script)
        case .verify:          verify(t, script)
        case .keywords:        keywords(t, script)
        case .fallback:        fallback(t, script)
        case .snapOCR:         snapOCR(t, script)
        }
    }

    // MARK: - Coach (选区命令改写) · 8200ms

    private static func coach(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.selectScale = t < 6150 ? easeInOut(p(t, 420, 1420)) : 0
        st.flashOpacity = t >= 6150 ? (1 - p(t, 6500, 7350)) : 0
        st.contentReplaced = t >= 6150

        // 选中文本改写 (`.rewriteSelection` → replaceSelection) is a configurable, empty-by-default
        // shortcut — NOT Fn Space (which is read-only 任意提问). Label by the action, not a fake key.
        st.hotkeyText = "改写选区键"
        st.hotkeyOpacity = windowed(t, 1320, 1540, 2200, 2500)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 1320, 1540)))
        st.hotkeyScale = (t > 1850 && t < 2150) ? 0.965 : 1

        let listening = t < 3400
        st.pillMode = listening ? .listening : .thinking
        st.pillLabel = listening ? s.listeningLabel : s.thinkingLabel
        st.pillOpacity = windowed(t, 1880, 2200, 5200, 6100)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 1880, 2200)))
        st.pillScale = lerp(0.98, 1, easeOut(p(t, 1880, 2200)))
        st.pillTime = listening ? mmss(t - 1880) : ""
        st.waveActive = listening && st.pillOpacity > 0.02

        st.panelOpacity = windowed(t, 2760, 3140, 6500, 7180)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 2760, 3140))) + lerp(0, -8, easeOut(p(t, 6500, 7180)))
        st.panelPrimaryActive = t >= 5660 && t < 6080
        return st
    }

    // MARK: - Dictate (听写) · 7600ms

    private static func dictate(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.flashOpacity = t >= 5120 ? (1 - p(t, 5520, 6300)) : 0
        st.contentReplaced = t >= 5120

        st.hotkeyText = "轻点 Fn"
        st.hotkeyOpacity = windowed(t, 420, 660, 1280, 1580)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 420, 660)))

        let listening = t < 3840
        st.pillMode = listening ? .listening : .thinking
        st.pillLabel = listening ? s.listeningLabel : s.thinkingLabel
        st.pillOpacity = windowed(t, 900, 1180, 5480, 6150)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 900, 1180)))
        st.pillTime = listening ? mmss(t - 960) : ""

        let n = s.wordTokens.count
        if t >= 1220 && t < 5120 {
            st.wordCount = min(n, Int(p(t, 1360, 3460) * Double(n + 1)))
        } else if t >= 5120 {
            st.wordCount = n
        }
        st.waveActive = listening && st.pillOpacity > 0.02
        return st
    }

    // MARK: - Translate (语音翻译) · 7000ms · 听中文 → 英文直写，无预览面板

    private static func translate(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.flashOpacity = t >= 5120 ? (1 - p(t, 5520, 6300)) : 0
        st.contentReplaced = t >= 5120

        st.hotkeyText = "Fn Shift"
        st.hotkeyOpacity = windowed(t, 420, 660, 1280, 1580)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 420, 660)))

        let listening = t < 3840
        st.pillMode = listening ? .listening : .thinking
        st.pillLabel = listening ? s.listeningLabel : s.thinkingLabel
        st.pillOpacity = windowed(t, 900, 1180, 5480, 6150)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 900, 1180)))
        st.pillTime = listening ? mmss(t - 960) : ""

        let n = s.wordTokens.count
        if t >= 1220 && t < 5120 {
            st.wordCount = min(n, Int(p(t, 1360, 3460) * Double(n + 1)))
        } else if t >= 5120 {
            st.wordCount = n
        }
        st.waveActive = listening && st.pillOpacity > 0.02
        return st
    }

    // MARK: - Ask Anything (无选区提问 / 快速操作) · 8400ms

    private static func english(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.flashOpacity = t >= 6420 ? (1 - p(t, 6900, 7800)) : 0
        st.contentReplaced = t >= 6420

        st.hotkeyText = "Fn Space"
        st.hotkeyOpacity = windowed(t, 560, 820, 1280, 1580)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 560, 820)))

        let listening = t < 3820
        st.pillMode = listening ? .listening : .thinking
        st.pillLabel = listening ? s.listeningLabel : s.thinkingLabel
        st.pillOpacity = windowed(t, 880, 1160, 6820, 7600)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 880, 1160)))
        st.pillTime = listening ? mmss(t - 900) : ""

        let n = s.wordTokens.count
        if t >= 1280 && t < 6420 {
            st.wordCount = min(n, Int(p(t, 1360, 3540) * Double(n + 1)))
        } else if t >= 6420 {
            st.wordCount = n
        }

        st.panelOpacity = windowed(t, 4920, 5280, 6900, 7700)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 4920, 5280))) + lerp(0, -8, easeOut(p(t, 6900, 7700)))
        st.panelPrimaryActive = t >= 6220 && t < 6420
        st.waveActive = listening && st.pillOpacity > 0.02
        return st
    }

    // MARK: - Select-translate (选区翻译 · 只读) · select → Fn Space → read-only card · 8000ms
    // Like `coach` but the source is NEVER replaced (contentReplaced stays false): the translation
    // shows only in the result card, and write-back is an explicit button. The selection stays
    // highlighted the whole loop and the loop rests on the read-only card.

    private static func selectTranslate(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.selectScale = easeInOut(p(t, 420, 1420))   // selection stays up: original is never replaced

        st.hotkeyText = "Fn Space"
        st.hotkeyOpacity = windowed(t, 1320, 1540, 2200, 2500)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 1320, 1540)))
        st.hotkeyScale = (t > 1850 && t < 2150) ? 0.965 : 1

        let listening = t < 3400
        st.pillMode = listening ? .listening : .thinking
        st.pillLabel = listening ? s.listeningLabel : s.thinkingLabel
        st.pillOpacity = windowed(t, 1880, 2200, 5200, 6100)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 1880, 2200)))
        st.pillScale = lerp(0.98, 1, easeOut(p(t, 1880, 2200)))
        st.pillTime = listening ? mmss(t - 1880) : ""
        st.waveActive = listening && st.pillOpacity > 0.02

        st.panelOpacity = windowed(t, 3000, 3400, 7300, 7950)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 3000, 3400)))
        st.panelPrimaryActive = t >= 5600 && t < 6000   // ⏎ 复制 (read-only) pulse — never writes back
        return st
    }

    // MARK: - Verify (来源核验) · select → extract → Xiong search → Song search → evidence cards · 12800ms

    private static func verify(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.selectScale = t < 10400 ? easeInOut(p(t, 420, 1420)) : 0

        // 划词菜单 pops over the selection, then 来源核验 highlights — the real entry point
        // (selectionMenu, not a hotkey). It fades before anchors reveal (3200ms), so the
        // existing extract/search/evidence beats are untouched.
        st.hotkeyText = "划词键"
        st.hotkeyOpacity = windowed(t, 700, 940, 1450, 1700)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 700, 940)))
        st.menuOpacity = windowed(t, 1500, 1760, 2650, 2900)
        st.menuHighlight = t >= 2100 && t < 2650

        st.pillMode = .thinking
        st.pillLabel = s.thinkingLabel
        st.pillOpacity = windowed(t, 1880, 2200, 10100, 10900)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 1880, 2200)))
        st.pillScale = lerp(0.98, 1, easeOut(p(t, 1880, 2200)))

        st.panelOpacity = windowed(t, 2800, 3200, 11600, 12300)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 2800, 3200))) + lerp(0, -8, easeOut(p(t, 11600, 12300)))

        if t >= 3200 && t < 3700 {
            st.anchorRevealCount = 1
        } else if t >= 3700 {
            st.anchorRevealCount = 2
        }

        if t >= 4800 && t < 5200 {
            st.anchorFlashIndex = 0
        } else if t >= 6600 && t < 7000 {
            st.anchorFlashIndex = 1
        }

        st.searchPageOpacity = windowed(t, 5200, 5600, 8000, 8400)
        if t >= 5200 && t < 6600 {
            st.searchFocusIndex = 0
            if t >= 6200 {
                st.matchRevealCount = 4
            } else if t >= 5900 {
                st.matchRevealCount = 2
            } else if t >= 5600 {
                st.matchRevealCount = 1
            }
        } else if t >= 6600 && t < 8400 {
            st.searchFocusIndex = 1
            if t >= 7600 {
                st.matchRevealCount = 4
            } else if t >= 7300 {
                st.matchRevealCount = 2
            } else if t >= 7000 {
                st.matchRevealCount = 1
            }
        }

        if t >= 8500 && t < 9200 {
            st.verifiedSourceRevealCount = 1
        } else if t >= 9200 {
            st.verifiedSourceRevealCount = 2
        }
        st.panelPrimaryActive = t >= 10000 && t < 10450
        return st
    }

    // MARK: - Keywords (检索关键词) · select → generate → groups → CNKI query → insert · 7400ms

    private static func keywords(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.selectScale = t < 5800 ? easeInOut(p(t, 520, 1220)) : 0
        st.flashOpacity = t >= 5800 ? (1 - p(t, 6000, 6400)) : 0
        st.contentReplaced = t >= 5800

        st.hotkeyText = "⌥L"
        st.hotkeyOpacity = windowed(t, 1080, 1320, 1780, 2080)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 1080, 1320)))
        st.hotkeyScale = (t > 1500 && t < 1740) ? 0.965 : 1

        st.pillMode = .thinking
        st.pillLabel = s.thinkingLabel
        st.pillOpacity = windowed(t, 1660, 1940, 6200, 6800)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 1660, 1940)))

        st.panelOpacity = windowed(t, 2500, 2900, 6200, 6800)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 2500, 2900))) + lerp(0, -8, easeOut(p(t, 6200, 6800)))

        if t >= 2900 && t < 3400 {
            st.keywordRevealCount = 1
        } else if t >= 3400 && t < 3900 {
            st.keywordRevealCount = 2
        } else if t >= 3900 {
            st.keywordRevealCount = 3
        }

        st.queryOpacity = easeOut(p(t, 4400, 4800))
        if t >= 6200 { st.queryOpacity = max(0, st.queryOpacity * (1 - p(t, 6200, 6800))) }

        st.panelPrimaryActive = t >= 5400 && t < 5800
        return st
    }

    // MARK: - Fallback (搜索引擎兜底) · select → 学术库查无 → 搜索引擎 URL 结果 · 8000ms

    private static func fallback(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()
        st.selectScale = easeInOut(p(t, 420, 1220)) * (1 - easeOut(p(t, 6200, 6600)))

        st.hotkeyText = "⌥L"
        st.hotkeyOpacity = windowed(t, 1080, 1320, 1780, 2080)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 1080, 1320)))
        st.hotkeyScale = (t > 1500 && t < 1740) ? 0.965 : 1

        st.pillMode = .thinking
        st.pillLabel = s.thinkingLabel
        st.pillOpacity = windowed(t, 1660, 2000, 6600, 7200)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 1660, 2000)))

        st.panelOpacity = windowed(t, 3200, 3600, 6600, 7200)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 3200, 3600))) + lerp(0, -8, easeOut(p(t, 6600, 7200)))

        if t >= 3600 && t < 4200 {
            st.urlRevealCount = 1
        } else if t >= 4200 {
            st.urlRevealCount = 2
        }

        st.panelPrimaryActive = t >= 5800 && t < 6200
        return st
    }

    // MARK: - Snap OCR (截图识别) · drag-select region → recognize → result panel · 8500ms

    private static func snapOCR(_ t: Double, _ s: FeatureDemoScript) -> DemoFrameState {
        var st = DemoFrameState()

        st.hotkeyText = "截图键"
        st.hotkeyOpacity = windowed(t, 400, 660, 1280, 1580)
        st.hotkeyOffsetY = lerp(7, 0, easeOut(p(t, 400, 660)))

        // drag-select the region: marquee grows in, holds, fades before the loop restarts
        st.marqueeScale = min(easeOut(p(t, 900, 1700)), 1 - easeOut(p(t, 7900, 8300)))

        // recognizing…
        st.pillMode = .thinking
        st.pillLabel = s.thinkingLabel
        st.pillOpacity = windowed(t, 2200, 2500, 4300, 4800)
        st.pillOffsetY = lerp(16, 0, easeOut(p(t, 2200, 2500)))

        // OCR result panel
        st.panelOpacity = windowed(t, 4300, 4700, 7900, 8400)
        st.panelOffsetY = lerp(18, 0, easeOut(p(t, 4300, 4700))) + lerp(0, -8, easeOut(p(t, 7900, 8400)))
        st.panelPrimaryActive = t >= 6100 && t < 6500

        // text extracted → drives the "已取字" toast (FeatureDemoView keys it off contentReplaced).
        // The .snap host renders from marqueeScale, not contentReplaced, so this is display-only.
        st.contentReplaced = t >= 4700
        return st
    }
}
