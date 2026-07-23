import SwiftUI
import ResponsayCore

/// 454 — the learning-audit card: the four-tier auto-learn ledger made visible and controllable.
/// Groups records into 待确认 / 已加入 / 未采纳 / 已撤销 (via `LearningAuditGroups`) and offers
/// approve / reject / undo. Split out of `DictionarySettingsPane` to keep that file under the
/// 400-line cap; pure view code over the same stores.
extension DictionarySettingsPane {
    var learningHistoryCard: some View {
        let groups = LearningAuditGroups(records: recentLearningRecords)
        let canClear = !groups.added.isEmpty || count(for: .auto) > 0 || !recentLearningRecords.isEmpty
        return WarmCard {
            HStack(spacing: 8) {
                GroupLabel(text: "学习记录")
                Spacer(minLength: 0)
                if canClear {
                    Button { showClearConfirm = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("清空")
                        }
                        .font(.system(size: SkinMetrics.fsLabel, weight: .medium))
                        .foregroundStyle(SettingsTheme.wine)
                    }
                    .buttonStyle(.plain)
                    .help("清空学习记录，并移除所有自动学到的词条（手动词不受影响）")
                    .accessibilityLabel("清空学习记录")
                }
            }
            Text("Responsay 从你的纠正里学到的词，全部存在本机。可逐条撤销；或点右上「清空」一次清掉全部学习记录与自动学到的词条（手动添加的词不受影响）。")
                .font(SettingsTheme.footnote)
                .foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)

            if groups.added.isEmpty {
                Text("暂无自动学习记录。")
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink3)
            } else {
                aliasReplayControl
                auditGroup("已加入", groups.added)
            }
        }
        .confirmationDialog("清空学习记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空（含已学词条）", role: .destructive) { clearLearning() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除学习日志和所有自动学到的词条；手动添加的词不受影响。此操作不可撤销。")
        }
    }

    @ViewBuilder
    func auditGroup(_ title: String, _ rows: [LearningAuditGroups.Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(title) · \(rows.count)")
                    .font(.system(size: SkinMetrics.fsLabel, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink2)
                ForEach(rows) { auditRow($0) }
            }
        }
    }

    func auditRow(_ row: LearningAuditGroups.Row) -> some View {
        let record = row.record
        return HStack(spacing: 8) {
            Image(systemName: recordStatusSymbol(record.status))
                .font(.system(size: SkinMetrics.fsCaption))
                .foregroundStyle(appearanceStore.palette.ink3)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(auditRowTitle(record))
                        .font(.system(size: SkinMetrics.fsFoot, weight: .medium))
                        .foregroundStyle(appearanceStore.palette.ink)
                        .lineLimit(1)
                    if isLearnedAlias(record) {
                        Text("alias")
                            .font(.system(size: SkinMetrics.fsCaption, weight: .semibold))
                            .foregroundStyle(appearanceStore.palette.ink2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(appearanceStore.palette.card2))
                    }
                    if let label = sensitivityLabel(row.sensitivityReason) {
                        Text(label)
                            .font(.system(size: SkinMetrics.fsCaption, weight: .semibold))
                            .foregroundStyle(SettingsTheme.wine)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(SettingsTheme.wineTint))
                            .help("专业词：低/中置信时先进「待确认」，不自动生效")
                    }
                }
                Text(auditRowSubtitle(row))
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            auditRowActions(record)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .fill(appearanceStore.palette.field))
    }

    @ViewBuilder
    func auditRowActions(_ record: HotwordLearningRecord) -> some View {
        switch record.status {
        case .pending:
            iconButton("checkmark", help: "批准加入词典") { confirm(record) }
            iconButton("xmark", help: "拒绝（不再学这个词）") { reject(record) }
        case .added:
            iconButton("arrow.uturn.backward", help: "撤销自动加入") { undo(record.term) }
        case .ignored, .undone:
            EmptyView()
        }
    }

    var aliasReplayControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WarmField(placeholder: "测试误识别文本，如 Cloud Code", text: $aliasReplayText)
                    .onSubmit(runAliasReplay)
                iconButton("play.fill", help: "本地测试 learned alias 命中", action: runAliasReplay)
                    .disabled(aliasReplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(aliasReplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            }
            if let aliasReplayResult {
                Text(aliasReplaySummary(aliasReplayResult))
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .lineLimit(2)
            }
        }
    }
}
