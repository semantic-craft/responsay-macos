import SwiftUI
import ResponsayCore
import AppKit

/// 主面板 (Overview, issue 152) — today / 7-day usage built from the local
/// `CaptureStore` via the tested `OverviewMetricsBuilder` (151), plus an
/// ASR/LLM/TTS readiness row derived from the saved provider selection (233).
/// Warm-paper, Scheme B; config-free, nothing leaves the machine.
struct OverviewScreen: View {
    @State private var metrics: OverviewMetrics = .empty
    @State private var metricsLoaded = false
    @State private var metricsUnavailable = false
    @State private var metricsNonce = 0
    /// 「看演示」 sheet (issue 314) for rewatching the same demos shown during
    /// onboarding.
    @State private var showDemos = false
    /// 382 — read-only model status strip, refreshed when the window re-activates so
    /// readiness reflects keys edited in 设置·模型. Readiness is Keychain-backed, so it's
    /// resolved OFF the main thread (398) — never in the @State initializer or synchronously
    /// on re-activate, which froze the 概览 (the lead tab) on every app switch.
    @State private var lanes: [ModelLaneInfo] = []
    @State private var lanesNonce = 0
    @Environment(AppearanceStore.self) private var appearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statsStrip
                    idiomaticCard
                    weekCard
                    demoCard
                    providerCard
                }
                .padding(22)
            }
        }
        .background(appearanceStore.palette.bg)
        .task(id: metricsNonce) {
            await refreshMetrics()
        }
        .task {
            await refreshAtNextLocalMidnight()
        }
        .task(id: lanesNonce) {
            // Keychain-backed readiness off the main thread; never block the 概览 render (398).
            let computed = await Task.detached(priority: .userInitiated) {
                ModelLaneDisplay().lanes()
            }.value
            guard !Task.isCancelled else { return }
            lanes = computed
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            metricsNonce &+= 1
            lanesNonce &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureStoreDidChange)) { _ in
            metricsNonce &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelConfigurationDidChange)) { _ in
            lanesNonce &+= 1
        }
        .sheet(isPresented: $showDemos) { demoSheet }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("主面板").font(.system(size: 22, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
            Text("今天与最近 7 天的听写概览 · 累计统计当前保留记录")
                .font(.system(size: 12.5)).foregroundStyle(appearanceStore.palette.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(appearanceStore.palette.hair).frame(height: 1) }
    }

    // MARK: Stats strip

    private var statsStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                statCard(metricText(metrics.todayCharacterCount), "字", "今天听写")
                statCard(metricText(metrics.todaySegmentCount), "段", "今天转写")
                statCard(metricText(metrics.totalSegmentCount), "段", "当前保留累计")
                statCard(savedText, savedUnit, "估算省下打字")
            }
            Text(metricsUnavailable
                 ? "暂时无法读取本机统计，请稍后重试。"
                 : "累计与省时估算覆盖当前保留的全部记录；省时按 3.5 字/秒估算。")
                .font(.system(size: 10.5))
                .foregroundStyle(metricsUnavailable ? SettingsTheme.amber : appearanceStore.palette.ink3)
        }
    }

    private func statCard(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
                Text(unit).font(.system(size: 12)).foregroundStyle(appearanceStore.palette.ink3)
            }
            Text(label).font(.system(size: 11.5)).foregroundStyle(appearanceStore.palette.ink2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }

    // MARK: 7-day chart

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近 7 天").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
                Spacer()
                Text("按字数").font(.system(size: 11)).foregroundStyle(appearanceStore.palette.ink3)
            }
            if metricsUnavailable {
                Text("本机统计暂时不可用。")
                    .font(.system(size: 12.5)).foregroundStyle(SettingsTheme.amber)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if !metricsLoaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if weekIsEmpty {
                Text("还没有记录。按热键说一句试试。")
                    .font(.system(size: 12.5)).foregroundStyle(appearanceStore.palette.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(metrics.last7Days) { bucket in
                        dayBar(bucket)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .warmCardSurface()
    }

    private func dayBar(_ bucket: OverviewDayBucket) -> some View {
        let maxChars = max(1, metrics.last7Days.map(\.characterCount).max() ?? 1)
        let frac = Double(bucket.characterCount) / Double(maxChars)
        let isToday = Calendar.current.isDateInToday(bucket.date)
        return VStack(spacing: 6) {
            Text("\(bucket.characterCount)")
                .font(.system(size: 10)).foregroundStyle(appearanceStore.palette.ink3)
                .opacity(bucket.characterCount > 0 ? 1 : 0)
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isToday ? appearanceStore.palette.accent : appearanceStore.palette.accentWash2)
                        .frame(height: max(3, geo.size.height * CGFloat(frac)))
                }
            }
            Text(weekday(bucket.date))
                .font(.system(size: 10.5, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? appearanceStore.palette.ink : appearanceStore.palette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 地道外文 entry (384 — discoverability)

    /// Surfaces 地道外文 (spoken/non-idiomatic target language → native phrasing + 为什么)
    /// so people know it exists
    /// and how to fire it. The live result lands in the coach capsule on the hotkey /
    /// menu-bar trigger; tapping here plays the demo so the gesture is unambiguous.
    private var idiomaticCard: some View {
        Button { showDemos = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(SettingsTheme.wine)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("地道外文").font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(appearanceStore.palette.ink)
                    Text("说目标外文或不顺的外文 → Native Speaker 说法，并给出红绿对照与「为什么这样说」。目标语言跟「听写翻译」联动；默认轻点右 Option 触发。")
                        .font(.system(size: 11.5)).foregroundStyle(appearanceStore.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("看演示").font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(appearanceStore.palette.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("地道外文：说目标外文获得 Native Speaker 说法，点击看演示")
    }

    // MARK: Feature demos (314)

    private var demoCard: some View {
        Button { showDemos = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(appearanceStore.palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("看演示").font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(appearanceStore.palette.ink)
                    Text("半分钟动画过一遍：听写、改写、翻译、地道外文与法律技能的真实用法。")
                        .font(.system(size: 11.5)).foregroundStyle(appearanceStore.palette.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("看功能演示")
    }

    private var demoSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("功能演示").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
                Spacer()
                Button("完成") { showDemos = false }.keyboardShortcut(.cancelAction)
            }
            .padding(EdgeInsets(top: 16, leading: 22, bottom: 12, trailing: 22))
            .overlay(alignment: .bottom) {
                Rectangle().fill(appearanceStore.palette.hair).frame(height: 1)
            }
            ScrollView {
                FeatureDemoShowcase(layout: .sheet).padding(28)
            }
        }
        .frame(width: 940, height: 820)
        .background(appearanceStore.palette.bg)
    }

    // MARK: Provider readiness

    /// 382 — read-only four-lane status strip. Model choice lives in 设置·模型 now;
    /// here we only show what's selected + configured, and clicking any row jumps there.
    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("模型状态").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(appearanceStore.palette.ink)
                Spacer()
                Button("管理模型") { openModelSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(appearanceStore.palette.accent)
            }
            VStack(spacing: 8) {
                ForEach(lanes) { laneStatusRow($0) }
            }
            Text("点任意一行去「设置·模型」选择或填密钥；状态表示是否选好/配好，不代表实时连通。")
                .font(.system(size: 11)).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCardSurface()
    }

    private func laneStatusRow(_ lane: ModelLaneInfo) -> some View {
        Button { openModelSettings() } label: {
            HStack(spacing: 10) {
                Circle().fill(readinessColor(lane.readiness)).frame(width: 7, height: 7)
                Text(lane.title).font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(appearanceStore.palette.ink).frame(width: 64, alignment: .leading)
                Text(lane.currentTitle).font(.system(size: 11.5)).foregroundStyle(appearanceStore.palette.ink2)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(readinessLabel(lane.readiness)).font(.system(size: 10.5))
                    .foregroundStyle(readinessColor(lane.readiness))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink3)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(appearanceStore.palette.card2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lane.title)：\(lane.currentTitle)，\(readinessLabel(lane.readiness))，点击去设置·模型")
    }

    private func openModelSettings() {
        MacSettingsWindowController.shared.show(section: .models)
    }

    private func readinessColor(_ r: ModelLaneReadiness) -> Color {
        switch r {
        case .local, .cloudReady: SettingsTheme.green
        case .localNotInstalled, .cloudUnconfigured: SettingsTheme.amber
        }
    }

    private func readinessLabel(_ r: ModelLaneReadiness) -> String {
        switch r {
        case .local: "本机就绪"
        case .localNotInstalled: "未下载"
        case .cloudReady: "已配置"
        case .cloudUnconfigured: "未配置"
        }
    }

    // MARK: Card shell


    // MARK: Data

    private func refreshMetrics() async {
        do {
            let computed = try await Task.detached(priority: .utility) {
                let status = ModelLaneDisplay.providerStatusSummary(
                    from: ModelLaneDisplay().lanes())
                return try Self.makeStore().overviewMetrics(
                    now: Date(),
                    calendar: .current,
                    status: status,
                    typingCharsPerSecond: OverviewMetricsBuilder.defaultTypingCharsPerSecond)
            }.value
            guard !Task.isCancelled else { return }
            metrics = computed
            metricsLoaded = true
            metricsUnavailable = false
        } catch {
            guard !Task.isCancelled else { return }
            metricsLoaded = false
            metricsUnavailable = true
        }
    }

    private func refreshAtNextLocalMidnight() async {
        while !Task.isCancelled {
            let now = Date()
            let calendar = Calendar.current
            guard let midnight = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime)
            else { return }
            do {
                try await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(now))))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            metricsNonce &+= 1
        }
    }

    private nonisolated static func makeStore() -> CaptureStore {
        if let sqlite = try? SQLiteReviewStore.defaultStore() {
            return ReviewCaptureStore(reviewStore: sqlite)
        }
        return FileCaptureStore.defaultStore()
    }

    // MARK: Helpers

    private var weekIsEmpty: Bool {
        metrics.last7Days.allSatisfy { $0.characterCount == 0 }
    }

    private func metricText(_ value: Int) -> String {
        metricsLoaded ? "\(value)" : "—"
    }

    private var savedText: String {
        guard metricsLoaded else { return "—" }
        let seconds = metrics.estimatedTypingSecondsSaved
        if seconds < 3600 { return "\(Int((seconds / 60).rounded()))" }
        return String(format: "%.1f", seconds / 3600)
    }

    private var savedUnit: String {
        guard metricsLoaded else { return "" }
        return metrics.estimatedTypingSecondsSaved < 3600 ? "分钟" : "小时"
    }

    private func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
