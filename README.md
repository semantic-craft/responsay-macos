<div align="center">
  <img src="macOS/Assets.xcassets/AppIcon.appiconset/MacIcon-512.png" width="112" alt="Responsay app icon">
  <h1>Responsay for macOS</h1>
  <p><strong>Speak naturally. Get writing that is ready to use.</strong></p>
  <p>A native, open-source voice input and writing assistant that works wherever you type on your Mac.</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a>
    ·
    <a href="https://responsay.com/">Website</a>
    ·
    <a href="https://github.com/semantic-craft/responsay-macos/releases/latest/download/Responsay.dmg"><strong>Download for macOS</strong></a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
    <a href="https://github.com/semantic-craft/responsay-macos/actions/workflows/ci.yml"><img src="https://github.com/semantic-craft/responsay-macos/actions/workflows/ci.yml/badge.svg" alt="Public source CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7B3651" alt="MIT License"></a>
  </p>
</div>

Responsay — **法言** in the app — turns speech into clean text inside the app you are already using. Press a global shortcut, speak, and let Responsay insert the result into Mail, Pages, Word, a browser, or almost any other macOS text field.

It goes beyond transcription. Responsay can translate as you speak, rewrite selected text, turn non-native phrasing into natural foreign-language expression, answer questions with the current selection as context, extract text from screenshots, read text aloud, and support source-aware legal writing workflows.

It is built especially for people who think faster than they type: writers, researchers, lawyers, students, and anyone who spends the day turning ideas into words.

## What you can do

| | Capability | What it feels like |
| --- | --- | --- |
| 🎙️ | **Dictate anywhere** | Speak naturally and get punctuated text in the active app. Choose faithful transcription or AI-assisted cleanup. |
| 🌏 | **Translate while speaking** | Say the source text and insert a faithful translation in the target language. |
| ✨ | **Sound natural in another language** | Speak imperfect English, German, Japanese, or another target language and get native-style phrasing with an explanation of what changed. |
| 🪄 | **Act on selected text** | Translate, rewrite, ask questions, normalize typography, read aloud, add terms to your recognition dictionary, or run an enabled skill. |
| 💬 | **Ask anything** | Ask by voice, optionally grounded in selected text or visible screen context. Answers appear in a read-only card before you copy or use them. |
| 📷 | **Capture text that cannot be selected** | Draw a region over an image, protected PDF, or another app; then extract, edit, copy, or translate the text. |
| ⚖️ | **Use source-aware legal tools** | Run legal writing skills, generate search strategies, and check candidate statutes, cases, and citations against source entry points. |
| 🔊 | **Listen instead of rereading** | Read selected text or assistant answers aloud with a local or cloud voice. |

Legal verification provides candidate evidence and links for human review. It does not replace checking the original source or making a professional legal judgment.

## Local when you want it, cloud when you need it

Responsay does not require a Responsay account or a Responsay-hosted backend.

- **No API key required:** use Apple system dictation, or download the local SenseVoice speech model and punctuation model for fully offline Chinese and English dictation.
- **Optional local models:** use PaddleOCR for offline image text recognition and Kokoro for offline read-aloud.
- **Bring your own keys:** connect the cloud ASR, LLM, OCR, or TTS provider you prefer when you want stronger transcription, rewriting, translation, search, or voices.
- **Direct connections:** cloud requests go from the app to the provider you selected. Responsay does not relay them through its own server.
- **Keychain storage:** API keys are stored in macOS Keychain, not in configuration files or logs.

Only the capability you invoke receives the relevant audio, text, or image. Provider pricing, retention, and data policies still apply when you use a cloud service.

## Get started

1. **[Download the latest DMG](https://github.com/semantic-craft/responsay-macos/releases/latest/download/Responsay.dmg)** and move Responsay to Applications.
2. Open the app and follow the first-run guide. Microphone access is needed for dictation; Accessibility access lets Responsay insert text into the active app.
3. Start with Apple dictation, download the offline foundation models, or add your own provider keys in Settings.
4. Press your dictation shortcut and say a sentence. Configure additional shortcuts for translation, Ask Anything, screenshot translation, and the selection menu when you need them.

**System requirement:** macOS 14 Sonoma or later. Screen Recording permission is requested only when you use a screen-capture feature; the rest of the app continues to work without it.

## Why Responsay is different

- **It works at the point of writing.** Results go into the current text field instead of being trapped in a separate chat window.
- **It keeps you in control.** Transformations that modify text are explicit; answers, source checks, and legal results remain reviewable before use.
- **It learns your vocabulary locally.** Corrected names and specialist terms can improve later recognition and remain on your Mac.
- **It supports real writing workflows.** Dictation, translation, OCR, source verification, style packs, and read-aloud share one native interface.
- **It is inspectable.** The macOS app and its cross-platform Swift core are public under the MIT License.

## Privacy and security

Local dictation, local OCR, local read-aloud, settings, usage metrics, and saved history stay on the Mac. When you enable a cloud feature, the relevant content is sent directly to the provider configured for that capability.

Before sharing a bug report, remove transcript text, selected content, file paths, account identifiers, and credentials from logs or screenshots.

Every pull request, push to `main`, and release runs a fixed public-source allowlist, Gitleaks, TruffleHog, deterministic privacy checks, tests, and a macOS build. Raw secret-scanner reports remain in temporary runner storage and are not uploaded as artifacts. Maintainer signing, notarization, and Sparkle credentials stay outside this repository.

## For contributors

Responsay is a native Swift 6 and SwiftUI app targeting macOS 14+. `ResponsayCore` contains the platform-independent capture, provider, OCR, skill, and writing logic. XcodeGen keeps the Xcode project reproducible.

```text
macOS/                         macOS UI and system integration
Packages/ResponsayCore/       Cross-platform Swift modules and unit tests
Tests/ResponsayMacTests/      macOS application tests
project.yml                   XcodeGen project definition
scripts/fetch-sherpa-onnx.sh  Fetches local inference dependencies not stored in Git
scripts/ci/                    Public-source and secret-scanning gates
scripts/release-macos.sh       Maintainer release driver
docs/RELEASING.md             Maintainer release guide
```

### Build from source

You need Xcode, Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and approximately 175 MB of prebuilt sherpa-onnx / ONNX Runtime development dependencies.

```bash
brew install xcodegen
scripts/fetch-sherpa-onnx.sh
xcodegen generate
xcodebuild -scheme ResponsayMac -destination 'platform=macOS'
```

`Responsay.xcodeproj` is generated and intentionally not tracked. The public project contains no fixed development team, release certificate, or private signing configuration.

### Run tests

```bash
swift test --package-path Packages/ResponsayCore
xcodegen generate
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS'
```

Microphone, Accessibility, global shortcuts, text insertion, Keychain, and screen capture still require manual verification on a real Mac.

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Dependencies and asset attribution are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Other platforms

This repository is the canonical source for the macOS app and `ResponsayCore`. The Windows version uses a separate Rust, Tauri, and React codebase in [`semantic-craft/responsay-windows`](https://github.com/semantic-craft/responsay-windows).

## License

Responsay is open source under the [MIT License](LICENSE).
