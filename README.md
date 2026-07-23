# 法言 · Responsay for macOS

法言是一款原生 macOS AI 语音输入与写作助手。按住全局热键说话，应用会完成语音识别、按所选模式整理文本，并把结果插入当前输入框；选中文本后还可以进行翻译、改写、提问和来源核验。

本仓库只包含 macOS 实现。Windows 版使用独立的 Rust、Tauri 和 React 技术栈，源码位于 [`semantic-craft/responsay-windows`](https://github.com/semantic-craft/responsay-windows)。

## 开发主仓

本仓库是 macOS 应用、`ResponsayCore` 和对应测试的唯一源码主仓。macOS 新功能应直接在这里开发；内部产品仓库只消费经过确认的公开提交，不作为这些目录的并行编辑源。贡献与跨仓同步规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 设计原则

- 原生 Swift 6、SwiftUI，最低支持 macOS 14。
- BYOK：云端 ASR、LLM、TTS 请求由应用直接发送到用户选择的提供商，没有 Responsay 后端中转。
- API 密钥只保存在 macOS Keychain，不写入配置文件或日志。
- 可选离线语音识别通过 sherpa-onnx 运行。
- 法律来源核验只提供候选证据和检索入口，不替用户作最终判断。
- 法言是使用全局热键和辅助功能完成输入的 accessory app，不是 InputMethodKit 输入源。

## 仓库结构

```text
macOS/                         macOS UI 与系统集成
Packages/ResponsayCore/       平台无关的 Swift 模块与单元测试
Tests/ResponsayMacTests/      macOS 应用测试
project.yml                   XcodeGen 工程定义
scripts/fetch-sherpa-onnx.sh  获取未纳入 Git 的本地推理依赖
scripts/ci/                    公共源码边界与秘密扫描门
scripts/release-macos.sh       GitHub hosted runner 发布驱动
docs/RELEASING.md             维护者发布手册
```

内部研究、发布凭证、签名身份、历史 issue、抓取页面、构建产物、模型和第三方归档不属于本公开仓库。

## 构建

需要 Xcode、Swift 6、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和约 175 MB 的 sherpa-onnx/ONNX Runtime 预编译依赖。

```bash
brew install xcodegen
scripts/fetch-sherpa-onnx.sh
xcodegen generate
xcodebuild -scheme ResponsayMac -destination 'platform=macOS'
```

`Responsay.xcodeproj` 由 XcodeGen 生成，不纳入 Git。公开工程不包含固定开发团队或发布证书；维护者的签名、公证和发布配置位于私有发布环境。

## 测试

```bash
swift test --package-path Packages/ResponsayCore
xcodegen generate
xcodebuild test -scheme ResponsayMac -destination 'platform=macOS'
```

涉及麦克风、辅助功能、全局热键、文本插入和屏幕录制权限的行为仍需在真实 Mac 上人工验证。

## 隐私与安全

使用云端功能时，语音或文本会发送给用户在设置中选择并配置的第三方提供商。提交 bug 前，请删除日志或截图中的转写文本、选区内容、文件路径、账户标识和凭证。

每个 pull request、`main` 推送和正式发布都会运行固定路径白名单、Gitleaks、TruffleHog 和补充的确定性检查。扫描原始报告只写入 runner 的临时目录，日志仅公开通过/失败状态，任务结束时立即删除，不作为 artifact 上传。

正式发布在 GitHub hosted macOS runner 上分为两个阶段：不带密钥的源码/测试预检，以及通过 `public-release` Environment 审批后才取得签名、公证密钥的发布阶段。配置和操作说明见 [docs/RELEASING.md](docs/RELEASING.md)。

## 第三方软件

依赖和素材归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。通知声音的完整 MIT 文本保留在 [`macOS/Resources/Sounds/NOTICE-orca-sounds.md`](macOS/Resources/Sounds/NOTICE-orca-sounds.md)。

## 许可证

本项目以 [MIT License](LICENSE) 开源。
