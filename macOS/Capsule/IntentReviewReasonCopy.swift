import ResponsayCore

/// Content-free capsule copy for each `safe-unavailable` reason (#559). Every string is a fixed
/// category label — it never embeds the transcript, the provider response, or the internal plan
/// (spec decision 29). `isRetryable` decides whether the card offers 重试: only faults a fresh
/// attempt could actually clear (outage / timeout / a bad-or-unsafe response) are retryable; a
/// missing key or an unsupported model is not — those point the user at 设置 / 转普通听写 instead.
enum IntentReviewReasonCopy {
    static func present(_ reason: IntentUnavailableReason) -> (title: String, body: String, isRetryable: Bool) {
        switch reason {
        case .compilerUnavailable:
            return ("未配置模型",
                    "还没配置可用的文本模型，或「校验成稿」实验已关闭。你的原话未写入任何应用。",
                    false)
        case .capabilityUnsupported:
            return ("当前模型不支持",
                    "所选模型暂不支持结构化校验成稿。可在「模型与密钥」换一个模型，或转普通听写。",
                    false)
        case .compilerFailed:
            return ("模型暂时不可用",
                    "网络或服务出错，未能生成结果。为避免误写，原话没有自动上屏。",
                    true)
        case .providerTimeout:
            return ("请求超时",
                    "这次等待过久已中止。可以重试，或转普通听写。",
                    true)
        case .invalidPlan:
            return ("结果未通过来源校验",
                    "模型返回的内容没通过安全校验，已被拦下——不会把不可信的内容写进你的文档。",
                    true)
        case .postRenderGuardRejected:
            return ("成稿未通过最终校验",
                    "成稿在最终安全校验时被拦下。可以重试，或转普通听写。",
                    true)
        case .invalidSource:
            return ("没有可整理的内容",
                    "这次没有识别到可成稿的内容。",
                    false)
        case .cancelled:
            return ("已取消",
                    "本次已取消，未写入任何内容。",
                    false)
        }
    }
}
