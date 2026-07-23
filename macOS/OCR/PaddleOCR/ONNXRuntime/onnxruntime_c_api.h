// Minimal ONNX Runtime C API declarations for Responsay's PaddleOCR bridge.
// Keep the OrtApi function-table order aligned with ONNX Runtime 1.13.x up to
// ReleaseSessionOptions. The vendored binary is still the source of truth; this
// header intentionally avoids vendoring the multi-thousand-line upstream header.

#ifndef RESPONSAY_MINIMAL_ONNXRUNTIME_C_API_H
#define RESPONSAY_MINIMAL_ONNXRUNTIME_C_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _In_
#define _In_
#define _In_opt_
#define _Inout_
#define _Out_
#define _Outptr_
#define _Outptr_result_maybenull_
#define _Outptr_result_buffer_maybenull_(X)
#define _In_z_
#define _In_reads_(X)
#define _Inout_updates_all_(X)
#define _Out_writes_all_(X)
#define _Out_writes_bytes_all_(X)
#endif

#ifndef ORT_API_CALL
#define ORT_API_CALL
#endif

#define ORT_API_VERSION 13
#define ORTCHAR_T char

typedef struct OrtAllocator OrtAllocator;
typedef struct OrtCustomOp OrtCustomOp;
typedef struct OrtCustomOpDomain OrtCustomOpDomain;
typedef struct OrtEnv OrtEnv;
typedef struct OrtKernelContext OrtKernelContext;
typedef struct OrtKernelInfo OrtKernelInfo;
typedef struct OrtMemoryInfo OrtMemoryInfo;
typedef struct OrtRunOptions OrtRunOptions;
typedef struct OrtSession OrtSession;
typedef struct OrtSessionOptions OrtSessionOptions;
typedef struct OrtStatus OrtStatus;
typedef struct OrtTensorTypeAndShapeInfo OrtTensorTypeAndShapeInfo;
typedef struct OrtTypeInfo OrtTypeInfo;
typedef struct OrtValue OrtValue;

typedef enum OrtErrorCode {
  ORT_OK = 0
} OrtErrorCode;

typedef enum OrtLoggingLevel {
  ORT_LOGGING_LEVEL_VERBOSE = 0,
  ORT_LOGGING_LEVEL_INFO = 1,
  ORT_LOGGING_LEVEL_WARNING = 2,
  ORT_LOGGING_LEVEL_ERROR = 3,
  ORT_LOGGING_LEVEL_FATAL = 4
} OrtLoggingLevel;

typedef enum ExecutionMode {
  ORT_SEQUENTIAL = 0,
  ORT_PARALLEL = 1
} ExecutionMode;

typedef enum GraphOptimizationLevel {
  ORT_DISABLE_ALL = 0,
  ORT_ENABLE_BASIC = 1,
  ORT_ENABLE_EXTENDED = 2,
  ORT_ENABLE_ALL = 99
} GraphOptimizationLevel;

typedef enum ONNXTensorElementDataType {
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED = 0,
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1
} ONNXTensorElementDataType;

typedef enum ONNXType {
  ONNX_TYPE_UNKNOWN = 0
} ONNXType;

typedef enum OrtAllocatorType {
  OrtInvalidAllocator = -1,
  OrtDeviceAllocator = 0,
  OrtArenaAllocator = 1
} OrtAllocatorType;

typedef enum OrtMemType {
  OrtMemTypeCPUInput = -2,
  OrtMemTypeCPUOutput = -1,
  OrtMemTypeDefault = 0
} OrtMemType;

typedef void (*OrtLoggingFunction)(
    void* param, OrtLoggingLevel severity, const char* category,
    const char* logid, const char* code_location, const char* message);

typedef OrtStatus* (ORT_API_CALL* OrtStatusVoidFn)(void);

typedef struct OrtApi {
  OrtStatus* (ORT_API_CALL* CreateStatus)(OrtErrorCode code, _In_ const char* msg);
  OrtErrorCode (ORT_API_CALL* GetErrorCode)(_In_ const OrtStatus* status);
  const char* (ORT_API_CALL* GetErrorMessage)(_In_ const OrtStatus* status);
  OrtStatus* (ORT_API_CALL* CreateEnv)(OrtLoggingLevel log_severity_level, _In_ const char* logid, _Outptr_ OrtEnv** out);
  OrtStatusVoidFn CreateEnvWithCustomLogger;
  OrtStatusVoidFn EnableTelemetryEvents;
  OrtStatusVoidFn DisableTelemetryEvents;
  OrtStatus* (ORT_API_CALL* CreateSession)(_In_ const OrtEnv* env, _In_ const ORTCHAR_T* model_path, _In_ const OrtSessionOptions* options, _Outptr_ OrtSession** out);
  OrtStatusVoidFn CreateSessionFromArray;
  OrtStatus* (ORT_API_CALL* Run)(_Inout_ OrtSession* session, _In_opt_ const OrtRunOptions* run_options, _In_reads_(input_len) const char* const* input_names, _In_reads_(input_len) const OrtValue* const* inputs, size_t input_len, _In_reads_(output_names_len) const char* const* output_names, size_t output_names_len, _Inout_updates_all_(output_names_len) OrtValue** outputs);
  OrtStatus* (ORT_API_CALL* CreateSessionOptions)(_Outptr_ OrtSessionOptions** options);
  OrtStatusVoidFn SetOptimizedModelFilePath;
  OrtStatusVoidFn CloneSessionOptions;
  OrtStatusVoidFn SetSessionExecutionMode;
  OrtStatusVoidFn EnableProfiling;
  OrtStatusVoidFn DisableProfiling;
  OrtStatusVoidFn EnableMemPattern;
  OrtStatusVoidFn DisableMemPattern;
  OrtStatusVoidFn EnableCpuMemArena;
  OrtStatusVoidFn DisableCpuMemArena;
  OrtStatusVoidFn SetSessionLogId;
  OrtStatusVoidFn SetSessionLogVerbosityLevel;
  OrtStatusVoidFn SetSessionLogSeverityLevel;
  OrtStatus* (ORT_API_CALL* SetSessionGraphOptimizationLevel)(_Inout_ OrtSessionOptions* options, GraphOptimizationLevel graph_optimization_level);
  OrtStatus* (ORT_API_CALL* SetIntraOpNumThreads)(_Inout_ OrtSessionOptions* options, int intra_op_num_threads);
  OrtStatus* (ORT_API_CALL* SetInterOpNumThreads)(_Inout_ OrtSessionOptions* options, int inter_op_num_threads);
  OrtStatusVoidFn CreateCustomOpDomain;
  OrtStatusVoidFn CustomOpDomain_Add;
  OrtStatusVoidFn AddCustomOpDomain;
  OrtStatusVoidFn RegisterCustomOpsLibrary;
  OrtStatusVoidFn SessionGetInputCount;
  OrtStatusVoidFn SessionGetOutputCount;
  OrtStatusVoidFn SessionGetOverridableInitializerCount;
  OrtStatusVoidFn SessionGetInputTypeInfo;
  OrtStatusVoidFn SessionGetOutputTypeInfo;
  OrtStatusVoidFn SessionGetOverridableInitializerTypeInfo;
  OrtStatus* (ORT_API_CALL* SessionGetInputName)(_In_ const OrtSession* session, size_t index, _Inout_ OrtAllocator* allocator, _Outptr_ char** value);
  OrtStatus* (ORT_API_CALL* SessionGetOutputName)(_In_ const OrtSession* session, size_t index, _Inout_ OrtAllocator* allocator, _Outptr_ char** value);
  OrtStatusVoidFn SessionGetOverridableInitializerName;
  OrtStatusVoidFn CreateRunOptions;
  OrtStatusVoidFn RunOptionsSetRunLogVerbosityLevel;
  OrtStatusVoidFn RunOptionsSetRunLogSeverityLevel;
  OrtStatusVoidFn RunOptionsSetRunTag;
  OrtStatusVoidFn RunOptionsGetRunLogVerbosityLevel;
  OrtStatusVoidFn RunOptionsGetRunLogSeverityLevel;
  OrtStatusVoidFn RunOptionsGetRunTag;
  OrtStatusVoidFn RunOptionsSetTerminate;
  OrtStatusVoidFn RunOptionsUnsetTerminate;
  OrtStatusVoidFn CreateTensorAsOrtValue;
  OrtStatus* (ORT_API_CALL* CreateTensorWithDataAsOrtValue)(_In_ const OrtMemoryInfo* info, _Inout_ void* p_data, size_t p_data_len, _In_ const int64_t* shape, size_t shape_len, ONNXTensorElementDataType type, _Outptr_ OrtValue** out);
  OrtStatusVoidFn IsTensor;
  OrtStatus* (ORT_API_CALL* GetTensorMutableData)(_In_ OrtValue* value, _Outptr_ void** out);
  OrtStatusVoidFn FillStringTensor;
  OrtStatusVoidFn GetStringTensorDataLength;
  OrtStatusVoidFn GetStringTensorContent;
  OrtStatusVoidFn CastTypeInfoToTensorInfo;
  OrtStatusVoidFn GetOnnxTypeFromTypeInfo;
  OrtStatusVoidFn CreateTensorTypeAndShapeInfo;
  OrtStatusVoidFn SetTensorElementType;
  OrtStatusVoidFn SetDimensions;
  OrtStatusVoidFn GetTensorElementType;
  OrtStatus* (ORT_API_CALL* GetDimensionsCount)(_In_ const OrtTensorTypeAndShapeInfo* info, _Out_ size_t* out);
  OrtStatus* (ORT_API_CALL* GetDimensions)(_In_ const OrtTensorTypeAndShapeInfo* info, _Out_ int64_t* dim_values, size_t dim_values_length);
  OrtStatusVoidFn GetSymbolicDimensions;
  OrtStatus* (ORT_API_CALL* GetTensorShapeElementCount)(_In_ const OrtTensorTypeAndShapeInfo* info, _Out_ size_t* out);
  OrtStatus* (ORT_API_CALL* GetTensorTypeAndShape)(_In_ const OrtValue* value, _Outptr_ OrtTensorTypeAndShapeInfo** out);
  OrtStatusVoidFn GetTypeInfo;
  OrtStatusVoidFn GetValueType;
  OrtStatusVoidFn CreateMemoryInfo;
  OrtStatus* (ORT_API_CALL* CreateCpuMemoryInfo)(OrtAllocatorType type, OrtMemType mem_type, _Outptr_ OrtMemoryInfo** out);
  OrtStatusVoidFn CompareMemoryInfo;
  OrtStatusVoidFn MemoryInfoGetName;
  OrtStatusVoidFn MemoryInfoGetId;
  OrtStatusVoidFn MemoryInfoGetMemType;
  OrtStatusVoidFn MemoryInfoGetType;
  OrtStatusVoidFn AllocatorAlloc;
  OrtStatus* (ORT_API_CALL* AllocatorFree)(_Inout_ OrtAllocator* ort_allocator, void* p);
  OrtStatusVoidFn AllocatorGetInfo;
  OrtStatus* (ORT_API_CALL* GetAllocatorWithDefaultOptions)(_Outptr_ OrtAllocator** out);
  OrtStatusVoidFn AddFreeDimensionOverride;
  OrtStatusVoidFn GetValue;
  OrtStatusVoidFn GetValueCount;
  OrtStatusVoidFn CreateValue;
  OrtStatusVoidFn CreateOpaqueValue;
  OrtStatusVoidFn GetOpaqueValue;
  OrtStatusVoidFn KernelInfoGetAttribute_float;
  OrtStatusVoidFn KernelInfoGetAttribute_int64;
  OrtStatusVoidFn KernelInfoGetAttribute_string;
  OrtStatusVoidFn KernelContext_GetInputCount;
  OrtStatusVoidFn KernelContext_GetOutputCount;
  OrtStatusVoidFn KernelContext_GetInput;
  OrtStatusVoidFn KernelContext_GetOutput;
  void (ORT_API_CALL* ReleaseEnv)(OrtEnv* input);
  void (ORT_API_CALL* ReleaseStatus)(OrtStatus* input);
  void (ORT_API_CALL* ReleaseMemoryInfo)(OrtMemoryInfo* input);
  void (ORT_API_CALL* ReleaseSession)(OrtSession* input);
  void (ORT_API_CALL* ReleaseValue)(OrtValue* input);
  void (ORT_API_CALL* ReleaseRunOptions)(OrtRunOptions* input);
  void (ORT_API_CALL* ReleaseTypeInfo)(OrtTypeInfo* input);
  void (ORT_API_CALL* ReleaseTensorTypeAndShapeInfo)(OrtTensorTypeAndShapeInfo* input);
  void (ORT_API_CALL* ReleaseSessionOptions)(OrtSessionOptions* input);
} OrtApi;

typedef struct OrtApiBase {
  const OrtApi* (ORT_API_CALL* GetApi)(uint32_t version);
  const char* (ORT_API_CALL* GetVersionString)(void);
} OrtApiBase;

const OrtApiBase* ORT_API_CALL OrtGetApiBase(void);

#ifdef __cplusplus
}
#endif

#endif
