import pkg/hyperx/errors

type GrpcStatusCode* = distinct uint8
proc `==`*(a, b: GrpcStatusCode): bool {.borrow.}
proc `$`*(a: GrpcStatusCode): string {.borrow.}

const
  grpcOk* = 0.GrpcStatusCode
  grpcCancelled* = 1.GrpcStatusCode
  grpcUnknown* = 2.GrpcStatusCode
  grpcInvalidArg* = 3.GrpcStatusCode
  grpcDeadlineEx* = 4.GrpcStatusCode
  grpcNotFound* = 5.GrpcStatusCode
  grpcAlreadyExists* = 6.GrpcStatusCode
  grpcPermissionDenied* = 7.GrpcStatusCode
  grpcResourceExhausted* = 8.GrpcStatusCode
  grpcFailedPrecondition* = 9.GrpcStatusCode
  grpcAborted* = 10.GrpcStatusCode
  grpcOutOfRange* = 11.GrpcStatusCode
  grpcUnimplemented* = 12.GrpcStatusCode
  grpcInternal* = 13.GrpcStatusCode
  grpcUnavailable* = 14.GrpcStatusCode
  grpcDataLoss* = 15.GrpcStatusCode
  grpcUnauthenticated* = 16.GrpcStatusCode

proc name*(code: GrpcStatusCode): string {.raises: [].} =
  result = case code:
  of grpcOk: "OK"
  of grpcCancelled: "CANCELLED"
  of grpcUnknown: "UNKNOWN"
  of grpcInvalidArg: "INVALID_ARGUMENT"
  of grpcDeadlineEx: "DEADLINE_EXCEEDED"
  of grpcNotFound: "NOT_FOUND"
  of grpcAlreadyExists: "ALREADY_EXISTS"
  of grpcPermissionDenied: "PERMISSION_DENIED"
  of grpcResourceExhausted: "RESOURCE_EXHAUSTED"
  of grpcFailedPrecondition: "FAILED_PRECONDITION"
  of grpcAborted: "ABORTED"
  of grpcOutOfRange: "OUT_OF_RANGE"
  of grpcUnimplemented: "UNIMPLEMENTED"
  of grpcInternal: "INTERNAL"
  of grpcUnavailable: "UNAVAILABLE"
  of grpcDataLoss: "DATA_LOSS"
  of grpcUnauthenticated: "UNAUTHENTICATED"
  else: doAssert false; ""

func toGrpcStatusCode*(code: HyperxErrCode): GrpcStatusCode {.raises: [].} =
  ## translate http2 codes to status codes; for internal use
  case code
  of hyxNoError,
      hyxProtocolError,
      hyxInternalError,
      hyxFlowControlError,
      hyxSettingsTimeout,
      hyxFrameSizeError,
      hyxCompressionError,
      hyxConnectError:
    grpcInternal
  of hyxRefusedStream:
    grpcUnavailable
  of hyxCancel:
    grpcCancelled
  of hyxEnhanceYourCalm:
    grpcResourceExhausted
  of hyxInadequateSecurity:
    grpcPermissionDenied
  #of hyxStreamClosed, hyxHttp11Required:
  else:
    grpcUnknown
