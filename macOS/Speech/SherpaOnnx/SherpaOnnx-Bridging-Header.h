// Bridging header exposing the sherpa-onnx C API to Swift (offline SenseVoice ASR).
// The xcframework is vendored via scripts/fetch-sherpa-onnx.sh (gitignored).
#import "c-api.h"
#import "PaddleORTSession.h"
#import "PaddleORTTensor.h"
