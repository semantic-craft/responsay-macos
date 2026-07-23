func sherpaOnnxOfflinePunctuationModelConfig(
  ctTransformer: String,
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu"
) -> SherpaOnnxOfflinePunctuationModelConfig {
  return SherpaOnnxOfflinePunctuationModelConfig(
    ct_transformer: toCPointer(ctTransformer),
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider)
  )
}

func sherpaOnnxOfflinePunctuationConfig(
  model: SherpaOnnxOfflinePunctuationModelConfig
) -> SherpaOnnxOfflinePunctuationConfig {
  return SherpaOnnxOfflinePunctuationConfig(
    model: model
  )
}

class SherpaOnnxOfflinePunctuationWrapper {
  /// A pointer to the underlying counterpart in C
  let ptr: OpaquePointer!

  /// Constructor taking a model config
  init(
    config: UnsafePointer<SherpaOnnxOfflinePunctuationConfig>!
  ) {
    ptr = SherpaOnnxCreateOfflinePunctuation(config)
  }

  deinit {
    if let ptr {
      SherpaOnnxDestroyOfflinePunctuation(ptr)
    }
  }

  func addPunct(text: String) -> String {
    let cText = SherpaOfflinePunctuationAddPunct(ptr, toCPointer(text))
    let ans = String(cString: cText!)
    SherpaOfflinePunctuationFreeText(cText)
    return ans
  }
}

func sherpaOnnxOnlinePunctuationModelConfig(
  cnnBiLstm: String,
  bpeVocab: String,
  numThreads: Int = 1,
  debug: Int = 0,
  provider: String = "cpu"
) -> SherpaOnnxOnlinePunctuationModelConfig {
  return SherpaOnnxOnlinePunctuationModelConfig(
    cnn_bilstm: toCPointer(cnnBiLstm),
    bpe_vocab: toCPointer(bpeVocab),
    num_threads: Int32(numThreads),
    debug: Int32(debug),
    provider: toCPointer(provider))
}

func sherpaOnnxOnlinePunctuationConfig(
  model: SherpaOnnxOnlinePunctuationModelConfig
) -> SherpaOnnxOnlinePunctuationConfig {
  return SherpaOnnxOnlinePunctuationConfig(model: model)
}

class SherpaOnnxOnlinePunctuationWrapper {
  /// A pointer to the underlying counterpart in C
  let ptr: OpaquePointer!

  /// Constructor taking a model config
  init(
    config: UnsafePointer<SherpaOnnxOnlinePunctuationConfig>!
  ) {
    ptr = SherpaOnnxCreateOnlinePunctuation(config)
  }

  deinit {
    if let ptr {
      SherpaOnnxDestroyOnlinePunctuation(ptr)
    }
  }

  func addPunct(text: String) -> String {
    let cText = SherpaOnnxOnlinePunctuationAddPunct(ptr, toCPointer(text))
    let ans = String(cString: cText!)
    SherpaOnnxOnlinePunctuationFreeText(cText)
    return ans
  }
}

