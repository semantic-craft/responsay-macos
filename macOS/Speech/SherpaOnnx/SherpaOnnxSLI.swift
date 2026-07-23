func sherpaOnnxSpokenLanguageIdentificationWhisperConfig(
  encoder: String,
  decoder: String,
  tailPaddings: Int = -1
) -> SherpaOnnxSpokenLanguageIdentificationWhisperConfig {
  return SherpaOnnxSpokenLanguageIdentificationWhisperConfig(
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    tail_paddings: Int32(tailPaddings))
}

func sherpaOnnxSpokenLanguageIdentificationConfig(
  whisper: SherpaOnnxSpokenLanguageIdentificationWhisperConfig,
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu"
) -> SherpaOnnxSpokenLanguageIdentificationConfig {
  return SherpaOnnxSpokenLanguageIdentificationConfig(
    whisper: whisper,
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider))
}

class SherpaOnnxSpokenLanguageIdentificationResultWrapper {
  /// A pointer to the underlying counterpart in C
  let result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>!

  /// Return the detected language.
  /// en for English
  /// zh for Chinese
  /// es for Spanish
  /// de for German
  /// etc.
  var lang: String {
    return String(cString: result.pointee.lang)
  }

  init(result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>!) {
    self.result = result
  }

  deinit {
    if let result {
      SherpaOnnxDestroySpokenLanguageIdentificationResult(result)
    }
  }
}

class SherpaOnnxSpokenLanguageIdentificationWrapper {
  /// A pointer to the underlying counterpart in C
  let slid: OpaquePointer!

  init(
    config: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationConfig>!
  ) {
    slid = SherpaOnnxCreateSpokenLanguageIdentification(config)
  }

  deinit {
    if let slid {
      SherpaOnnxDestroySpokenLanguageIdentification(slid)
    }
  }

  func decode(samples: [Float], sampleRate: Int = 16000)
    -> SherpaOnnxSpokenLanguageIdentificationResultWrapper
  {
    let stream: OpaquePointer! = SherpaOnnxSpokenLanguageIdentificationCreateOfflineStream(slid)
    SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))

    let result: UnsafePointer<SherpaOnnxSpokenLanguageIdentificationResult>? =
      SherpaOnnxSpokenLanguageIdentificationCompute(
        slid,
        stream)

    SherpaOnnxDestroyOfflineStream(stream)
    return SherpaOnnxSpokenLanguageIdentificationResultWrapper(result: result)
  }
}

// keyword spotting

