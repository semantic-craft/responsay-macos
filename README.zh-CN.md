<div align="center">
  <img src="macOS/Assets.xcassets/AppIcon.appiconset/MacIcon-512.png" width="112" alt="法言应用图标">
  <h1>法言 · Responsay for macOS</h1>
  <p><strong>自然开口，落字成文。</strong></p>
  <p>一款原生、开源、能在 Mac 任意输入位置工作的 AI 语音输入与写作助手。</p>
  <p>
    <a href="README.md">English</a>
    ·
    <a href="https://responsay.com/">官方网站</a>
    ·
    <a href="https://github.com/semantic-craft/responsay-macos/releases/latest/download/Responsay.dmg"><strong>下载 macOS 版</strong></a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7B3651" alt="MIT License"></a>
  </p>
</div>

法言把你的自然表达直接变成当前应用里的干净文字。按下全局快捷键，说出想法，结果就能进入邮件、Pages、Word、浏览器或几乎任何 macOS 输入框，不必在聊天窗口与文档之间来回复制。

它也不只做转写：你可以边说边翻译，把不够地道的外语变成 Native Speaker 的说法；选中文字后改写、提问或核验来源；从图片和受保护的 PDF 中截图取字；朗读长文；还可以用法律技能完成更有来源意识的写作与检索工作。

如果你思考得比打字快——无论是写作者、研究者、法律人、学生，还是每天都要把想法变成文字的人——法言都希望替你缩短“想到”与“写好”之间的距离。

## 你可以用法言做什么

| | 能力 | 实际体验 |
| --- | --- | --- |
| 🎙️ | **在任何应用听写** | 自然说话，在当前输入框得到带标点的文字；可选择如实转写或 AI 轻度清稿。 |
| 🌏 | **边说边翻译** | 说出中文或原文，直接插入忠实、准确的目标语言译文。 |
| ✨ | **把外语说得更地道** | 用不够自然的英语、德语、日语等表达，得到 Native Speaker 式改写和修改理由。 |
| 🪄 | **对选中文字继续工作** | 翻译、改写、提问、规范排版、朗读、加入识别词典，或运行已启用的技能。 |
| 💬 | **任意提问** | 用语音提问，也可以带上选区或屏幕可见内容作为上下文；答案先进入只读卡片，再由你决定如何使用。 |
| 📷 | **处理无法选中的文字** | 框选图片、受保护的 PDF 或其他应用区域，取字后编辑、复制或翻译。 |
| ⚖️ | **使用有来源意识的法律工具** | 运行法律写作技能、生成检索策略，并从法条、案例和文献入口核对候选引注。 |
| 🔊 | **用耳朵校对和阅读** | 使用本机或云端语音朗读选区与回答，减少反复盯屏。 |

法律来源核验只提供候选证据、核对状态和原始来源入口，不能代替阅读原文，也不会替用户作最终法律判断。

## 想本机就本机，需要云端再用云端

法言不要求注册 Responsay 账户，也没有 Responsay 自建后端中转你的内容。

- **零 API Key 也能开始：**直接使用 Apple 系统听写，或下载本机 SenseVoice 与标点模型，实现完全离线的中英文听写。
- **本机能力可继续扩展：**PaddleOCR 可离线识别图片文字，Kokoro 可离线朗读。
- **云端模型由你选择：**需要更强的转写、改写、翻译、搜索或语音时，再接入你偏好的 ASR、LLM、OCR 或 TTS 服务商。
- **请求直接发送：**云端请求由应用直接发给你选择的服务商，不经过 Responsay 服务器。
- **密钥留在钥匙串：**API Key 只保存在 macOS Keychain，不写入配置文件或日志。

只有你主动调用的能力会取得相应的语音、文字或图片。使用云端服务时，仍应留意该服务商自己的价格、留存和数据政策。

## 四步开始使用

1. **[下载最新版 DMG](https://github.com/semantic-craft/responsay-macos/releases/latest/download/Responsay.dmg)**，把 Responsay 移入“应用程序”。
2. 打开应用并完成首次引导。听写需要麦克风权限；把结果写入当前应用需要辅助功能权限。
3. 先用 Apple 系统听写、下载离线基础模型，或在设置中加入自己的服务商 API Key。
4. 按下听写快捷键说一句话。需要时，再为听写翻译、任意提问、截图翻译和划词菜单设置快捷键。

**系统要求：**macOS 14 Sonoma 或更高版本。只有使用截图功能时才会请求屏幕录制权限；不授权不会影响听写、改写和普通输入。

## 法言有什么不同

- **它就在写作发生的地方。**结果进入当前输入框，而不是困在另一个聊天窗口里。
- **是否改动文字由你决定。**会替换正文的操作是明确的；回答、来源核验和法律技能结果先供你审阅。
- **它能在本机记住你的词。**被纠正的人名、术语和专有词可以改善后续识别，并留在当前 Mac。
- **它围绕完整工作流设计。**听写、翻译、OCR、来源核验、文风技能和朗读共享一套原生交互。
- **它的实现可检查。**macOS 应用与跨平台 Swift 核心均以 MIT License 公开。

## 隐私与安全

本机听写、本机 OCR、本机朗读、设置、使用统计和保存的历史记录都留在当前 Mac。启用云端能力时，相关内容只会直接发给该能力所配置的服务商。

提交 bug 前，请删除日志或截图中的转写文本、选区内容、文件路径、账户标识和凭证。

每个 Origin pull request 和 `main` 合并都会运行固定路径白名单、Gitleaks、TruffleHog、补充的确定性隐私检查、测试和 Apple Silicon macOS 构建。秘密扫描原始报告只存在于 runner 临时目录，不上传为 artifact。维护者的签名、公证和 Sparkle 凭证始终位于仓库之外。

## 参与开发

法言使用原生 Swift 6 与 SwiftUI，最低支持 macOS 14。`ResponsayCore` 承载平台无关的采集、服务商、OCR、技能与写作逻辑；XcodeGen 用于生成可复现的 Xcode 工程。

Cursor Origin 的 [`xianwei/responsay-macos`](https://origin.cursor.com/xianwei/responsay-macos) 是 macOS 应用、`ResponsayCore` 和对应测试的唯一开发主仓。新分支、代码审查和 pull request 都在 Origin 完成；GitHub 只保留为归档与 issue tracker，并在现有更新与下载地址迁走前暂时公开。贡献、CI 与跨仓规则见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [docs/operations/ci.md](docs/operations/ci.md)。

```text
macOS/                         macOS UI 与系统集成
Packages/ResponsayCore/       跨平台 Swift 模块与单元测试
Tests/ResponsayMacTests/      macOS 应用测试
project.yml                   XcodeGen 工程定义
scripts/fetch-sherpa-onnx.sh  获取未纳入 Git 的本地推理依赖
scripts/ci/                    公开源码边界与秘密扫描门
scripts/release-macos.sh       维护者发布驱动
docs/RELEASING.md             维护者发布手册
```

### 从源码构建

需要 Xcode、Swift 6、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和约 175 MB 的 sherpa-onnx / ONNX Runtime 预编译开发依赖。

```bash
brew install xcodegen
scripts/fetch-sherpa-onnx.sh
xcodegen generate
xcodebuild -scheme ResponsayMac -destination 'platform=macOS'
```

`Responsay.xcodeproj` 由 XcodeGen 生成，因此不纳入 Git。公开工程不包含固定开发团队、发布证书或私有签名配置。

### 运行测试

```bash
swift test --package-path Packages/ResponsayCore
xcodegen generate
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS'
```

麦克风、辅助功能、全局快捷键、文本插入、Keychain 和屏幕捕捉仍需在真实 Mac 上人工验证。

提交 pull request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。依赖和素材归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 其他平台

本仓库是 macOS 应用与 `ResponsayCore` 的唯一源码主仓。Windows 版使用独立的 Rust、Tauri 和 React 技术栈，源码位于 [`semantic-craft/responsay-windows`](https://github.com/semantic-craft/responsay-windows)。

## 许可证

法言以 [MIT License](LICENSE) 开源。
