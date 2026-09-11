import Foundation
import Observation

@MainActor
protocol AudioOutputMuteBackend: AnyObject {
    var defaultOutputUID: String? { get }
    func mute(for uid: String) -> UInt32?
    func setMute(_ value: UInt32, for uid: String) -> Bool
    func observe(_ change: @escaping @MainActor (String?, UInt32?) -> Void)
    func stopObserving()
}

/// Owns only output changes made by this app. Durable records are keyed by UID,
/// never by transient AudioDeviceID or whichever device happens to be default.
@MainActor @Observable
final class AudioOutputMuter {
    static let shared = AudioOutputMuter(backend: CoreAudioOutputMuteBackend())
    static let recoveryKey = "audioMute.deviceRecovery.v1"
    static let legacyKey = "audioMute.priorMute"

    private let backend: AudioOutputMuteBackend
    private let defaults: UserDefaults
    private var records: [String: UInt32]
    private var confirmed = Set<String>()
    private var activeUID: String?
    private var overridden = Set<String>()
    private var engaged = false
    private var ready = false
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var muteWarning: String?
    private var hasLegacyRecord = false
    var recoveryNotice: String? {
        if hasLegacyRecord {
            return "发现旧版静音恢复记录，无法确认原输出设备。请在系统声音设置中检查原设备的静音状态；应用不会自动更改其他设备。"
        }
        if records.keys.contains(where: { $0 != activeUID }) {
            return "部分输出设备尚未恢复声音。应用会在设备可用时重试；也可在系统声音设置中手动取消静音。"
        }
        return muteWarning
    }

    init(backend: AudioOutputMuteBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        records = (defaults.dictionary(forKey: Self.recoveryKey) ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.uint32Value }
    }

    var isOutputMutedByApp: Bool { !confirmed.isEmpty }

    func engage(afterDelay delay: TimeInterval) {
        guard !engaged else { return }
        engaged = true
        muteWarning = nil
        overridden.removeAll()
        generation += 1
        let token = generation
        startObservation()
        if delay <= 0 {
            ready = true
            reconcile()
        } else {
            pending = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.engaged, self.generation == token else { return }
                self.pending = nil
                self.ready = true
                self.reconcile()
            }
        }
    }

    func disengage() {
        engaged = false
        ready = false
        generation += 1
        pending?.cancel()
        pending = nil
        activeUID = nil
        restoreOutstanding()
        updateMonitoring()
    }

    func recoverStuckMuteIfNeeded() {
        // An old record has no device identity. Preserve it for manual recovery.
        hasLegacyRecord = defaults.object(forKey: Self.legacyKey) != nil
        guard !engaged else { return }
        restoreOutstanding()
        updateMonitoring()
    }

    private func startObservation() {
        backend.observe { [weak self] uid, value in
            guard let self else { return }
            if let uid, let value, self.records[uid] != nil, value != 1 {
                self.confirmed.remove(uid)
                self.records.removeValue(forKey: uid)
                self.overridden.insert(uid)
                self.persist()
            }
            self.reconcile()
        }
    }

    private func reconcile() {
        if let uid = activeUID, records[uid] != nil, let value = backend.mute(for: uid), value != 1 {
            records.removeValue(forKey: uid)
            confirmed.remove(uid)
            overridden.insert(uid)
            persist()
        }
        let next = engaged && ready ? backend.defaultOutputUID : nil
        if activeUID != next {
            activeUID = nil
            restoreOutstanding()
            activeUID = next
        } else {
            restoreOutstanding()
        }
        if let uid = activeUID, !overridden.contains(uid), records[uid] == nil {
            if let prior = backend.mute(for: uid), prior == 0 {
                // Write ahead: an exit between the hardware write and persistence
                // must still leave a device-specific recovery record.
                records[uid] = prior
                guard persist() else {
                    records.removeValue(forKey: uid)
                    defaults.set(records, forKey: Self.recoveryKey)
                    muteWarning = "无法保存声音恢复记录，本次未执行静音。请检查系统声音设置。"
                    updateMonitoring()
                    return
                }
                let wrote = backend.setMute(1, for: uid)
                if !wrote || backend.mute(for: uid) != 1 {
                    if backend.mute(for: uid) == prior {
                        records.removeValue(forKey: uid)
                        persist()
                    }
                    muteWarning = "当前输出设备未能确认静音。请检查系统声音设置；录音可能收进背景声音。"
                } else {
                    muteWarning = nil
                    confirmed.insert(uid)
                }
            } else if backend.mute(for: uid) == nil {
                muteWarning = "当前输出设备不支持读取静音状态。请在系统声音设置中手动检查；录音可能收进背景声音。"
            }
        }
        updateMonitoring()
    }

    private func restoreOutstanding() {
        for (uid, prior) in records where uid != activeUID {
            guard let current = backend.mute(for: uid) else { continue }
            // A differing value means the user (or another app) has taken over.
            if current != 1 { overridden.insert(uid) }
            if current != 1 || (backend.setMute(prior, for: uid) && backend.mute(for: uid) == prior) {
                records.removeValue(forKey: uid)
                confirmed.remove(uid)
                persist()
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        defaults.set(records, forKey: Self.recoveryKey)
        // This is a write-ahead recovery journal, so the mute write must wait
        // for persistence instead of relying on UserDefaults' deferred flush.
        return defaults.synchronize()
    }

    private func updateMonitoring() {
        if engaged || !records.isEmpty {
            startObservation()
            if retry == nil {
                retry = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        guard let self else { return }
                        self.reconcile()
                    }
                }
            }
        } else {
            backend.stopObserving()
            retry?.cancel()
            retry = nil
        }
    }
}
