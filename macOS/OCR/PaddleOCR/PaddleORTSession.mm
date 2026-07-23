#import "PaddleORTSession.h"
#import "PaddleORTTensor.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import "ONNXRuntime/onnxruntime_c_api.h"
#pragma clang diagnostic pop
#include <vector>

static NSString *const PaddleORTErrorDomain = @"com.semanticcraft.responsay.paddleort";

@interface PaddleORTSession () {
    const OrtApi *_api;
    OrtEnv *_env;
    OrtSession *_session;
    OrtSessionOptions *_options;
    OrtAllocator *_allocator;
    OrtMemoryInfo *_memoryInfo;
    char *_inputName;
    char *_outputName;
}
@end

@implementation PaddleORTSession

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                threadCount:(NSInteger)threadCount
                                      error:(NSError **)error {
    self = [super init];
    if (!self) { return nil; }

    _api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (![self check:_api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "responsay-paddleocr", &_env) error:error]) {
        return nil;
    }
    if (![self check:_api->CreateSessionOptions(&_options) error:error]) { return nil; }
    int threads = (int)MAX(1, threadCount);
    if (![self check:_api->SetIntraOpNumThreads(_options, threads) error:error]) { return nil; }
    if (![self check:_api->SetInterOpNumThreads(_options, 1) error:error]) { return nil; }
    if (![self check:_api->SetSessionGraphOptimizationLevel(_options, ORT_ENABLE_ALL) error:error]) {
        return nil;
    }
    if (![self check:_api->CreateSession(_env, modelPath.fileSystemRepresentation, _options, &_session)
             error:error]) {
        return nil;
    }
    if (![self check:_api->GetAllocatorWithDefaultOptions(&_allocator) error:error]) { return nil; }
    if (![self check:_api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &_memoryInfo)
             error:error]) {
        return nil;
    }
    if (![self check:_api->SessionGetInputName(_session, 0, _allocator, &_inputName) error:error]) {
        return nil;
    }
    if (![self check:_api->SessionGetOutputName(_session, 0, _allocator, &_outputName) error:error]) {
        return nil;
    }
    return self;
}

- (nullable PaddleORTTensor *)runWithFloatData:(NSData *)floatData
                                         shape:(NSArray<NSNumber *> *)shape
                                         error:(NSError **)error {
    NSMutableData *mutableInput = [floatData mutableCopy];
    NSMutableArray<NSNumber *> *shapeNumbers = [shape mutableCopy];
    std::vector<int64_t> dims;
    dims.reserve(shapeNumbers.count);
    for (NSNumber *n in shapeNumbers) {
        dims.push_back(n.longLongValue);
    }

    OrtValue *input = nullptr;
    if (![self check:_api->CreateTensorWithDataAsOrtValue(
            _memoryInfo,
            mutableInput.mutableBytes,
            mutableInput.length,
            dims.data(),
            dims.size(),
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &input) error:error]) {
        return nil;
    }

    const char *inputNames[] = { _inputName };
    const char *outputNames[] = { _outputName };
    const OrtValue *inputs[] = { input };
    OrtValue *output = nullptr;
    BOOL ok = [self check:_api->Run(_session, nullptr, inputNames, inputs, 1, outputNames, 1, &output)
                    error:error];
    _api->ReleaseValue(input);
    if (!ok) { return nil; }

    OrtTensorTypeAndShapeInfo *info = nullptr;
    if (![self check:_api->GetTensorTypeAndShape(output, &info) error:error]) {
        _api->ReleaseValue(output);
        return nil;
    }

    size_t dimCount = 0;
    if (![self check:_api->GetDimensionsCount(info, &dimCount) error:error]) {
        _api->ReleaseTensorTypeAndShapeInfo(info);
        _api->ReleaseValue(output);
        return nil;
    }
    std::vector<int64_t> outDims(dimCount);
    if (![self check:_api->GetDimensions(info, outDims.data(), dimCount) error:error]) {
        _api->ReleaseTensorTypeAndShapeInfo(info);
        _api->ReleaseValue(output);
        return nil;
    }
    size_t elementCount = 0;
    if (![self check:_api->GetTensorShapeElementCount(info, &elementCount) error:error]) {
        _api->ReleaseTensorTypeAndShapeInfo(info);
        _api->ReleaseValue(output);
        return nil;
    }

    void *raw = nullptr;
    if (![self check:_api->GetTensorMutableData(output, &raw) error:error]) {
        _api->ReleaseTensorTypeAndShapeInfo(info);
        _api->ReleaseValue(output);
        return nil;
    }
    NSData *data = [NSData dataWithBytes:raw length:elementCount * sizeof(float)];
    NSMutableArray<NSNumber *> *outShape = [NSMutableArray arrayWithCapacity:dimCount];
    for (int64_t d : outDims) {
        [outShape addObject:@(d)];
    }

    _api->ReleaseTensorTypeAndShapeInfo(info);
    _api->ReleaseValue(output);
    return [[PaddleORTTensor alloc] initWithFloatData:data shape:outShape];
}

- (BOOL)check:(OrtStatus *)status error:(NSError **)error {
    if (status == nullptr) { return YES; }
    const char *message = _api ? _api->GetErrorMessage(status) : "ONNX Runtime error";
    NSString *text = message ? [NSString stringWithUTF8String:message] : @"ONNX Runtime error";
    if (error) {
        *error = [NSError errorWithDomain:PaddleORTErrorDomain
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: text}];
    }
    if (_api) { _api->ReleaseStatus(status); }
    return NO;
}

- (void)dealloc {
    if (_allocator && _inputName) { (void)_api->AllocatorFree(_allocator, _inputName); }
    if (_allocator && _outputName) { (void)_api->AllocatorFree(_allocator, _outputName); }
    if (_memoryInfo) { _api->ReleaseMemoryInfo(_memoryInfo); }
    if (_session) { _api->ReleaseSession(_session); }
    if (_options) { _api->ReleaseSessionOptions(_options); }
    if (_env) { _api->ReleaseEnv(_env); }
}

@end
