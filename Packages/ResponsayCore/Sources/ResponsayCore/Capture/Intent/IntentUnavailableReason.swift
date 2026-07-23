import Foundation

/// Why Intent-aware Dictate could not safely auto-insert. Each case maps to a distinct,
/// content-free capsule explanation (#559): the review UX must let the user tell "no key"
/// from "bad response" from "verifier rejected" without leaking the request or plan.
public enum IntentUnavailableReason: String, Sendable, Equatable {
    /// 无 Key / 未配置模型 / 实验关闭 / 无授权编译路由.
    case compilerUnavailable
    /// provider 的结构化 plan 能力不支持（#548 能力门；本阶段只经注入到达）。
    case capabilityUnsupported
    /// provider 不可达 / 连接失败 / HTTP 错误.
    case compilerFailed
    /// 请求超时（本阶段只经注入到达；传输层把 timeout 折叠进 network 字符串，不臆造区分）。
    case providerTimeout
    /// 没有可整理的内容（空 source）。
    case invalidSource
    /// 坏响应：空/坏 JSON、缺字段、越界、未过来源校验（plan verifier 拒）。
    case invalidPlan
    /// 成稿未过最终 post-render guard（verifier 拒绝）。
    case postRenderGuardRejected
    /// 本次已取消。
    case cancelled
}
