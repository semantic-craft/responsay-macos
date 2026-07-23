func sherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig(model: String = "")
  -> SherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig
{
  return SherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig(model: toCPointer(model))
}

func sherpaOnnxOfflineSpeechDenoiserDpdfNetModelConfig(model: String = "")
  -> SherpaOnnxOfflineSpeechDenoiserDpdfNetModelConfig
{
  return SherpaOnnxOfflineSpeechDenoiserDpdfNetModelConfig(model: toCPointer(model))
}

func sherpaOnnxOfflineSpeechDenoiserModelConfig(
  gtcrn: SherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig =
    sherpaOnnxOfflineSpeechDenoiserGtcrnModelConfig(),
  dpdfnet: SherpaOnnxOfflineSpeechDenoiserDpdfNetModelConfig =
    sherpaOnnxOfflineSpeechDenoiserDpdfNetModelConfig(),
  numThreads: Int = 1,
  provider: String = "cpu",
  debug: Int = 0
) -> SherpaOnnxOfflineSpeechDenoiserModelConfig {
  return SherpaOnnxOfflineSpeechDenoiserModelConfig(
    gtcrn: gtcrn,
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider),
    dpdfnet: dpdfnet
  )
}

func sherpaOnnxOfflineSpeechDenoiserConfig(
  model: SherpaOnnxOfflineSpeechDenoiserModelConfig =
    sherpaOnnxOfflineSpeechDenoiserModelConfig()
) -> SherpaOnnxOfflineSpeechDenoiserConfig {
  return SherpaOnnxOfflineSpeechDenoiserConfig(
    model: model)
}

class SherpaOnnxDenoisedAudioWrapper {
  /// A pointer to the underlying counterpart in C
  let audio: UnsafePointer<SherpaOnnxDenoisedAudio>!

  init(audio: UnsafePointer<SherpaOnnxDenoisedAudio>!) {
    self.audio = audio
  }

  deinit {
    if let audio {
      SherpaOnnxDestroyDenoisedAudio(audio)
    }
  }

  var n: Int32 {
    guard let audio else {
      return 0
    }
    return audio.pointee.n
  }

  var sampleRate: Int32 {
    guard let audio else {
      return 0
    }
    return audio.pointee.sample_rate
  }

  var samples: [Float] {
    guard let audio else {
      return []
    }

    if let p = audio.pointee.samples {
      var samples: [Float] = []
      for index in 0..<n {
        samples.append(p[Int(index)])
      }
      return samples
    } else {
      let samples: [Float] = []
      return samples
    }
  }

  func save(filename: String) -> Int32 {
    guard let audio else {
      return 0
    }
    return SherpaOnnxWriteWave(audio.pointee.samples, n, sampleRate, toCPointer(filename))
  }
}

class SherpaOnnxOfflineSpeechDenoiserWrapper {
  /// A pointer to the underlying counterpart in C
  let impl: OpaquePointer!

  /// Constructor taking a model config
  init(
    config: UnsafePointer<SherpaOnnxOfflineSpeechDenoiserConfig>!
  ) {
    impl = SherpaOnnxCreateOfflineSpeechDenoiser(config)
  }

  deinit {
    if let impl {
      SherpaOnnxDestroyOfflineSpeechDenoiser(impl)
    }
  }

  func run(samples: [Float], sampleRate: Int) -> SherpaOnnxDenoisedAudioWrapper {
    let audio: UnsafePointer<SherpaOnnxDenoisedAudio>? = SherpaOnnxOfflineSpeechDenoiserRun(
      impl, samples, Int32(samples.count), Int32(sampleRate))

    return SherpaOnnxDenoisedAudioWrapper(audio: audio)
  }

  var sampleRate: Int {
    return Int(SherpaOnnxOfflineSpeechDenoiserGetSampleRate(impl))
  }
}

func sherpaOnnxOnlineSpeechDenoiserConfig(
  model: SherpaOnnxOfflineSpeechDenoiserModelConfig =
    sherpaOnnxOfflineSpeechDenoiserModelConfig()
) -> SherpaOnnxOnlineSpeechDenoiserConfig {
  return SherpaOnnxOnlineSpeechDenoiserConfig(model: model)
}

class SherpaOnnxOnlineSpeechDenoiserWrapper {
  let impl: OpaquePointer!

  init(
    config: UnsafePointer<SherpaOnnxOnlineSpeechDenoiserConfig>!
  ) {
    impl = SherpaOnnxCreateOnlineSpeechDenoiser(config)
  }

  deinit {
    if let impl {
      SherpaOnnxDestroyOnlineSpeechDenoiser(impl)
    }
  }

  func run(samples: [Float], sampleRate: Int) -> SherpaOnnxDenoisedAudioWrapper {
    let audio: UnsafePointer<SherpaOnnxDenoisedAudio>? = SherpaOnnxOnlineSpeechDenoiserRun(
      impl, samples, Int32(samples.count), Int32(sampleRate))
    return SherpaOnnxDenoisedAudioWrapper(audio: audio)
  }

  func flush() -> SherpaOnnxDenoisedAudioWrapper {
    let audio: UnsafePointer<SherpaOnnxDenoisedAudio>? = SherpaOnnxOnlineSpeechDenoiserFlush(impl)
    return SherpaOnnxDenoisedAudioWrapper(audio: audio)
  }

  func reset() {
    SherpaOnnxOnlineSpeechDenoiserReset(impl)
  }

  var sampleRate: Int {
    return Int(SherpaOnnxOnlineSpeechDenoiserGetSampleRate(impl))
  }

  var frameShiftInSamples: Int {
    return Int(SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples(impl))
  }
}

func getSherpaOnnxVersion() -> String {
  return String(cString: SherpaOnnxGetVersionStr())
}

func getSherpaOnnxGitSha1() -> String {
  return String(cString: SherpaOnnxGetGitSha1())
}

func getSherpaOnnxGitDate() -> String {
  return String(cString: SherpaOnnxGetGitDate())
}
