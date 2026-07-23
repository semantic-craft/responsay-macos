#if DEBUG
import SwiftUI
import ResponsayCore

/// DEBUG-only diagnostics panel (issue 200): a live, structured feed of the ASR + TTS
/// speech stack. Observes `DiagnosticsCenter.shared`; newest events first, colored by
/// level, filterable by category, tap a row to expand its fields. Not shipped in release.
struct DiagnosticsPanelView: View {
    @State private var center = DiagnosticsCenter.shared
    @State private var filter: DiagnosticEvent.Category?
    @State private var expanded: Set<UUID> = []

    private var rows: [DiagnosticEvent] {
        let all = filter.map { center.events(in: $0) } ?? center.events.reversed().map { $0 }
        return all
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            latencySummary
            if rows.isEmpty {
                Spacer()
                Text("暂无事件 — 触发一次朗读/听写")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { row($0) }
                } .padding(8) }
            }
        }
        .frame(minWidth: 340, minHeight: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("诊断 · 语音栈").font(.headline)
            Spacer()
            Picker("", selection: $filter) {
                Text("全部").tag(DiagnosticEvent.Category?.none)
                Text("ASR").tag(DiagnosticEvent.Category?.some(.asr))
                Text("TTS").tag(DiagnosticEvent.Category?.some(.tts))
                Text("延迟").tag(DiagnosticEvent.Category?.some(.pipeline))
                Text("学习").tag(DiagnosticEvent.Category?.some(.autolearn))
            }.pickerStyle(.segmented).fixedSize()
            Button("清空") { center.clear() }.controlSize(.small)
        }.padding(8)
    }

    /// 507: session p50/p95 of end-to-end 听写 latency. Hidden until a dictation has run.
    @ViewBuilder
    private var latencySummary: some View {
        let totals = center.pipelineTotalsMs()
        if let p50 = LatencyStats.percentile(totals, 50) {
            let p95 = LatencyStats.percentile(totals, 95) ?? p50
            HStack(spacing: 4) {
                Text("听写延迟  p50 \(Int(p50))ms · p95 \(Int(p95))ms · n=\(totals.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            Divider()
        }
    }

    @ViewBuilder
    private func row(_ event: DiagnosticEvent) -> some View {
        let isOpen = expanded.contains(event.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(color(event.level)).frame(width: 7, height: 7)
                Text(event.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text(event.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(event.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            if let msg = event.errorMessage {
                Text(msg).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
            }
            if isOpen, !event.fields.isEmpty {
                ForEach(event.fields.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    Text("\(k): \(v)").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen { expanded.remove(event.id) } else { expanded.insert(event.id) }
        }
    }

    private func color(_ level: DiagnosticEvent.Level) -> Color {
        switch level { case .info: .secondary; case .warning: .orange; case .error: .red }
    }
}
#endif
