//---------------------------
// Source separation
//---------------------------

struct AudioData {
  private enum Storage {
    case owned([Float])
    case wrapped(ManagedWave)
  }

  private class ManagedWave {
    let pointer: UnsafePointer<SherpaOnnxMultiChannelWave>
    init(_ p: UnsafePointer<SherpaOnnxMultiChannelWave>) { self.pointer = p }
    deinit { SherpaOnnxFreeMultiChannelWave(pointer) }
  }

  private let storage: Storage
  let channelCount: Int
  let samplesPerChannel: Int
  let sampleRate: Int

  init(samples: [Float], channelCount: Int, sampleRate: Int) {
    self.storage = .owned(samples)
    self.channelCount = channelCount
    self.sampleRate = sampleRate
    self.samplesPerChannel = channelCount > 0 ? samples.count / channelCount : 0
  }

  init?(filename: String) {
    guard let ptr = SherpaOnnxReadWaveMultiChannel(filename) else { return nil }
    self.storage = .wrapped(ManagedWave(ptr))
    self.channelCount = Int(ptr.pointee.num_channels)
    self.samplesPerChannel = Int(ptr.pointee.num_samples)
    self.sampleRate = Int(ptr.pointee.sample_rate)
  }

  func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Float>) -> R) -> R {
    switch storage {
    case .owned(let array):
      return array.withUnsafeBufferPointer(body)
    case .wrapped(let managed):
      let total = Int(managed.pointer.pointee.num_channels * managed.pointer.pointee.num_samples)
      // Ensure we start from the first channel's pointer
      return body(UnsafeBufferPointer(start: managed.pointer.pointee.samples[0], count: total))
    }
  }

  @discardableResult
  func save(to filename: String) -> Bool {
    return withUnsafeBufferPointer { buf in
      guard let base = buf.baseAddress else { return false }
      // FIX: Explicitly type the array as Optional pointers to match C 'float* const*'
      var ptrs: [UnsafePointer<Float>?] = (0..<channelCount).map { base + ($0 * samplesPerChannel) }

      return SherpaOnnxWriteWaveMultiChannel(
        &ptrs,
        Int32(samplesPerChannel),
        Int32(sampleRate),
        Int32(channelCount),
        filename
      ) == 1
    }
  }
}

struct SourceSeparationConfig {
  struct Spleeter {
    var vocals: String
    var accompaniment: String
  }
  struct Uvr { var model: String }

  var spleeter: Spleeter?
  var uvr: Uvr?
  var numThreads: Int = 1
  var debug: Bool = false
  var provider: String = "cpu"

  func withCConfig<R>(_ body: (UnsafePointer<SherpaOnnxOfflineSourceSeparationConfig>) -> R) -> R {
    var cConfig = SherpaOnnxOfflineSourceSeparationConfig()
    cConfig.model.num_threads = Int32(self.numThreads)
    cConfig.model.debug = self.debug ? 1 : 0

    var s: [String: [Int8]] = [:]
    func b(_ k: String, _ v: String?) -> UnsafePointer<Int8>? {
      guard let v = v else { return nil }
      s[k] = Array(v.utf8CString)
      return s[k]!.withUnsafeBufferPointer { $0.baseAddress }
    }

    cConfig.model.provider = b("provider", self.provider)
    cConfig.model.spleeter.vocals = b("spleeter.vocals", self.spleeter?.vocals)
    cConfig.model.spleeter.accompaniment = b("spleeter.accompaniment", self.spleeter?.accompaniment)
    cConfig.model.uvr.model = b("uvr.model", self.uvr?.model)

    return body(&cConfig)
  }
}

class SourceSeparator {
  private var engine: OpaquePointer?

  init?(config: SourceSeparationConfig) {
    self.engine = config.withCConfig { SherpaOnnxCreateOfflineSourceSeparation($0) }

    if self.engine == nil { return nil }
  }

  deinit {
    if let e = engine {
      SherpaOnnxDestroyOfflineSourceSeparation(e)
    }
  }

  func process(buffer: AudioData) -> [AudioData]? {
    guard let engine = engine else { return nil }

    return buffer.withUnsafeBufferPointer { flatBuf in
      guard let base = flatBuf.baseAddress else { return nil }
      var ptrs: [UnsafePointer<Float>?] = (0..<buffer.channelCount).map {
        base + ($0 * buffer.samplesPerChannel)
      }

      guard
        let raw = SherpaOnnxOfflineSourceSeparationProcess(
          engine,
          &ptrs,
          Int32(buffer.channelCount),
          Int32(buffer.samplesPerChannel),
          Int32(buffer.sampleRate)
        )
      else { return nil }

      let stemCount = Int(raw.pointee.num_stems)
      let result = (0..<stemCount).map { i in
        let stem = raw.pointee.stems[i]
        let chs = Int(stem.num_channels)
        let n = Int(stem.n)
        var flat = [Float](repeating: 0, count: chs * n)

        for c in 0..<chs {
          if let src = stem.samples[c] {
            let offset = c * n
            flat.withUnsafeMutableBufferPointer { dest in
              let destPtr = dest.baseAddress!.advanced(by: offset)
              destPtr.initialize(from: src, count: n)
            }
          }
        }
        return AudioData(
          samples: flat, channelCount: chs, sampleRate: Int(raw.pointee.sample_rate))
      }

      SherpaOnnxDestroySourceSeparationOutput(raw)
      return result
    }
  }
}
