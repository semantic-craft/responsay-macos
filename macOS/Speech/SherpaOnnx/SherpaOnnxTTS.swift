import Foundation
import OSLog

func sherpaOnnxOfflineTtsVitsModelConfig(
  model: String = "",
  lexicon: String = "",
  tokens: String = "",
  dataDir: String = "",
  noiseScale: Float = 0.667,
  noiseScaleW: Float = 0.8,
  lengthScale: Float = 1.0,
  dictDir: String = ""
) -> SherpaOnnxOfflineTtsVitsModelConfig {
  return SherpaOnnxOfflineTtsVitsModelConfig(
    model: toCPointer(model),
    lexicon: toCPointer(lexicon),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    noise_scale: noiseScale,
    noise_scale_w: noiseScaleW,
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir)
  )
}

func sherpaOnnxOfflineTtsMatchaModelConfig(
  acousticModel: String = "",
  vocoder: String = "",
  lexicon: String = "",
  tokens: String = "",
  dataDir: String = "",
  noiseScale: Float = 0.667,
  lengthScale: Float = 1.0,
  dictDir: String = ""
) -> SherpaOnnxOfflineTtsMatchaModelConfig {
  return SherpaOnnxOfflineTtsMatchaModelConfig(
    acoustic_model: toCPointer(acousticModel),
    vocoder: toCPointer(vocoder),
    lexicon: toCPointer(lexicon),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    noise_scale: noiseScale,
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir)
  )
}

func sherpaOnnxOfflineTtsKokoroModelConfig(
  model: String = "",
  voices: String = "",
  tokens: String = "",
  dataDir: String = "",
  lengthScale: Float = 1.0,
  dictDir: String = "",
  lexicon: String = "",
  lang: String = ""
) -> SherpaOnnxOfflineTtsKokoroModelConfig {
  return SherpaOnnxOfflineTtsKokoroModelConfig(
    model: toCPointer(model),
    voices: toCPointer(voices),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    length_scale: lengthScale,
    dict_dir: toCPointer(dictDir),
    lexicon: toCPointer(lexicon),
    lang: toCPointer(lang)
  )
}

func sherpaOnnxOfflineTtsKittenModelConfig(
  model: String = "",
  voices: String = "",
  tokens: String = "",
  dataDir: String = "",
  lengthScale: Float = 1.0
) -> SherpaOnnxOfflineTtsKittenModelConfig {
  return SherpaOnnxOfflineTtsKittenModelConfig(
    model: toCPointer(model),
    voices: toCPointer(voices),
    tokens: toCPointer(tokens),
    data_dir: toCPointer(dataDir),
    length_scale: lengthScale
  )
}

func sherpaOnnxOfflineTtsZipvoiceModelConfig(
  tokens: String = "",
  encoder: String = "",
  decoder: String = "",
  vocoder: String = "",
  dataDir: String = "",
  lexicon: String = "",
  featScale: Float = 0.1,
  tShift: Float = 0.5,
  targetRms: Float = 0.1,
  guidanceScale: Float = 1.0
) -> SherpaOnnxOfflineTtsZipvoiceModelConfig {
  return SherpaOnnxOfflineTtsZipvoiceModelConfig(
    tokens: toCPointer(tokens),
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    vocoder: toCPointer(vocoder),
    data_dir: toCPointer(dataDir),
    lexicon: toCPointer(lexicon),
    feat_scale: featScale,
    t_shift: tShift,
    target_rms: targetRms,
    guidance_scale: guidanceScale
  )
}

func sherpaOnnxOfflineTtsPocketModelConfig(
  lmFlow: String = "",
  lmMain: String = "",
  encoder: String = "",
  decoder: String = "",
  textConditioner: String = "",
  vocabJson: String = "",
  tokenScoresJson: String = "",
  voiceEmbeddingCacheCapacity: Int = 50
) -> SherpaOnnxOfflineTtsPocketModelConfig {
  return SherpaOnnxOfflineTtsPocketModelConfig(
    lm_flow: toCPointer(lmFlow),
    lm_main: toCPointer(lmMain),
    encoder: toCPointer(encoder),
    decoder: toCPointer(decoder),
    text_conditioner: toCPointer(textConditioner),
    vocab_json: toCPointer(vocabJson),
    token_scores_json: toCPointer(tokenScoresJson),
    voice_embedding_cache_capacity: Int32(voiceEmbeddingCacheCapacity)
  )
}

func sherpaOnnxOfflineTtsSupertonicModelConfig(
  durationPredictor: String = "",
  textEncoder: String = "",
  vectorEstimator: String = "",
  vocoder: String = "",
  ttsJson: String = "",
  unicodeIndexer: String = "",
  voiceStyle: String = ""
) -> SherpaOnnxOfflineTtsSupertonicModelConfig {
  return SherpaOnnxOfflineTtsSupertonicModelConfig(
    duration_predictor: toCPointer(durationPredictor),
    text_encoder: toCPointer(textEncoder),
    vector_estimator: toCPointer(vectorEstimator),
    vocoder: toCPointer(vocoder),
    tts_json: toCPointer(ttsJson),
    unicode_indexer: toCPointer(unicodeIndexer),
    voice_style: toCPointer(voiceStyle)
  )
}

func sherpaOnnxOfflineTtsModelConfig(
  vits: SherpaOnnxOfflineTtsVitsModelConfig = sherpaOnnxOfflineTtsVitsModelConfig(),
  matcha: SherpaOnnxOfflineTtsMatchaModelConfig = sherpaOnnxOfflineTtsMatchaModelConfig(),
  kokoro: SherpaOnnxOfflineTtsKokoroModelConfig = sherpaOnnxOfflineTtsKokoroModelConfig(),
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu",
  kitten: SherpaOnnxOfflineTtsKittenModelConfig = sherpaOnnxOfflineTtsKittenModelConfig(),
  zipvoice: SherpaOnnxOfflineTtsZipvoiceModelConfig = sherpaOnnxOfflineTtsZipvoiceModelConfig(),
  pocket: SherpaOnnxOfflineTtsPocketModelConfig = sherpaOnnxOfflineTtsPocketModelConfig(),
  supertonic: SherpaOnnxOfflineTtsSupertonicModelConfig =
    sherpaOnnxOfflineTtsSupertonicModelConfig()
) -> SherpaOnnxOfflineTtsModelConfig {
  return SherpaOnnxOfflineTtsModelConfig(
    vits: vits,
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider),
    matcha: matcha,
    kokoro: kokoro,
    kitten: kitten,
    zipvoice: zipvoice,
    pocket: pocket,
    supertonic: supertonic
  )
}

func sherpaOnnxOfflineTtsConfig(
  model: SherpaOnnxOfflineTtsModelConfig,
  ruleFsts: String = "",
  ruleFars: String = "",
  maxNumSentences: Int = 1,
  silenceScale: Float = 0.2
) -> SherpaOnnxOfflineTtsConfig {
  return SherpaOnnxOfflineTtsConfig(
    model: model,
    rule_fsts: toCPointer(ruleFsts),
    max_num_sentences: Int32(maxNumSentences),
    rule_fars: toCPointer(ruleFars),
    silence_scale: silenceScale
  )
}

class SherpaOnnxWaveWrapper {
  let wave: UnsafePointer<SherpaOnnxWave>!

  class func readWave(filename: String) -> SherpaOnnxWaveWrapper {
    let wave = SherpaOnnxReadWave(toCPointer(filename))
    return SherpaOnnxWaveWrapper(wave: wave)
  }

  init(wave: UnsafePointer<SherpaOnnxWave>!) {
    self.wave = wave
  }

  deinit {
    if let wave {
      SherpaOnnxFreeWave(wave)
    }
  }

  var numSamples: Int {
    return Int(wave.pointee.num_samples)
  }

  var sampleRate: Int {
    return Int(wave.pointee.sample_rate)
  }

  var samples: [Float] {
    if numSamples == 0 {
      return []
    } else {
      return [Float](UnsafeBufferPointer(start: wave.pointee.samples, count: numSamples))
    }
  }
}

class SherpaOnnxGeneratedAudioWrapper {
  /// A pointer to the underlying counterpart in C
  let audio: UnsafePointer<SherpaOnnxGeneratedAudio>!

  init(audio: UnsafePointer<SherpaOnnxGeneratedAudio>!) {
    self.audio = audio
  }

  deinit {
    if let audio {
      SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)
    }
  }

  var n: Int32 {
    return audio.pointee.n
  }

  var sampleRate: Int32 {
    return audio.pointee.sample_rate
  }

  var samples: [Float] {
    if let p = audio.pointee.samples {
      return [Float](UnsafeBufferPointer(start: p, count: Int(n)))
    } else {
      return []
    }
  }

  func save(filename: String) -> Int32 {
    return SherpaOnnxWriteWave(audio.pointee.samples, n, sampleRate, toCPointer(filename))
  }
}

typealias TtsCallbackWithArg = (
  @convention(c) (
    UnsafePointer<Float>?,  // const float* samples
    Int32,  // int32_t n
    UnsafeMutableRawPointer?  // void *arg
  ) -> Int32
)?

class SherpaOnnxCallbackPair {
  var cb: TtsCallbackWithArg
  var arg: UnsafeMutableRawPointer?
  init(cb: TtsCallbackWithArg, arg: UnsafeMutableRawPointer?) {
    self.cb = cb
    self.arg = arg
  }
}

typealias TtsProgressCallbackWithArg =
  @convention(c) (
    UnsafePointer<Float>?, Int32, Float, UnsafeMutableRawPointer?
  ) -> Int32

struct SherpaOnnxGenerationConfigSwift {
  var silenceScale: Float = 0.2
  var speed: Float = 1.0
  var sid: Int = 0
  var referenceAudio: [Float] = []
  var referenceSampleRate: Int = 16000
  var referenceText: String = ""
  var numSteps: Int = 1
  var extra: [String: Any] = [:]  // Any can be String, Int, Float, Double

  /// Convert the extra dictionary into a JSON string
  func extraJsonString() -> String {
    var jsonCompatible: [String: Any] = [:]

    for (key, value) in extra {
      switch value {
      case let v as String:
        jsonCompatible[key] = v
      case let v as Int:
        jsonCompatible[key] = v
      case let v as Float:
        jsonCompatible[key] = v
      case let v as Double:
        jsonCompatible[key] = v
      default:
        // ignore unsupported types
        Logger(subsystem: "com.semanticcraft.responsay.mac", category: "tts-sherpa")
          .warning("unsupported type for key '\(key, privacy: .public)' in extra")
      }
    }

    guard let data = try? JSONSerialization.data(withJSONObject: jsonCompatible, options: []),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }

    return json
  }
}
final class SherpaOnnxGenerationConfigC {
  /// The underlying C struct
  var cConfig: SherpaOnnxGenerationConfig

  /// Storage for reference audio so the pointer stays valid during the C call
  private let referenceAudioStorage: [Float]

  /// Extra JSON string for C API
  let extraJson: String

  init(_ swiftConfig: SherpaOnnxGenerationConfigSwift) {
    let referenceAudio = swiftConfig.referenceAudio

    let extraJson = swiftConfig.extraJsonString()
    self.extraJson = extraJson

    self.referenceAudioStorage = referenceAudio

    self.cConfig = self.referenceAudioStorage.withUnsafeBufferPointer { buffer in
      SherpaOnnxGenerationConfig(
        silence_scale: swiftConfig.silenceScale,
        speed: swiftConfig.speed,
        sid: Int32(swiftConfig.sid),
        reference_audio: buffer.count > 0 ? buffer.baseAddress : nil,
        reference_audio_len: Int32(buffer.count),
        reference_sample_rate: Int32(swiftConfig.referenceSampleRate),
        reference_text: toCPointer(swiftConfig.referenceText),
        num_steps: Int32(swiftConfig.numSteps),
        extra: toCPointer(extraJson)
      )
    }
  }
}

class SherpaOnnxOfflineTtsWrapper {
  /// A pointer to the underlying counterpart in C
  let tts: OpaquePointer!

  /// Constructor taking a model config
  init(
    config: UnsafePointer<SherpaOnnxOfflineTtsConfig>!
  ) {
    tts = SherpaOnnxCreateOfflineTts(config)
  }

  deinit {
    if let tts {
      SherpaOnnxDestroyOfflineTts(tts)
    }
  }

  func generate(text: String, sid: Int = 0, speed: Float = 1.0) -> SherpaOnnxGeneratedAudioWrapper {
    let config = SherpaOnnxGenerationConfigSwift(speed: speed, sid: sid)
    return generateWithConfig(text: text, config: config, callback: nil, arg: nil)
  }

  func generateWithCallbackWithArg(
    text: String, callback: TtsCallbackWithArg, arg: UnsafeMutableRawPointer, sid: Int = 0,
    speed: Float = 1.0
  ) -> SherpaOnnxGeneratedAudioWrapper {
    let config = SherpaOnnxGenerationConfigSwift(speed: speed, sid: sid)

    let pair = SherpaOnnxCallbackPair(cb: callback, arg: arg)
    let unmanaged = Unmanaged.passRetained(pair)
    let wrapper: TtsProgressCallbackWithArg = { samples, n, progress, rawArg in
      let p = Unmanaged<SherpaOnnxCallbackPair>.fromOpaque(rawArg!).takeUnretainedValue()
      return p.cb!(samples, n, p.arg)
    }
    let result = generateWithConfig(
      text: text, config: config, callback: wrapper, arg: unmanaged.toOpaque())
    unmanaged.release()
    return result
  }

  func generateWithConfig(
    text: String,
    config: SherpaOnnxGenerationConfigSwift,
    callback: TtsProgressCallbackWithArg?,
    arg: UnsafeMutableRawPointer?
  ) -> SherpaOnnxGeneratedAudioWrapper {
    let bridge = SherpaOnnxGenerationConfigC(config)

    let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? =
      withUnsafePointer(to: &bridge.cConfig) { configPtr in
        SherpaOnnxOfflineTtsGenerateWithConfig(
          tts,
          toCPointer(text),
          configPtr,
          callback,
          arg
        )
      }

    return SherpaOnnxGeneratedAudioWrapper(audio: audio)
  }

}

// spoken language identification

