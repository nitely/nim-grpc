import pkg/hyperx/errors

# XXX GrpcStatusCode
type StatusCode* = distinct uint8
proc `==`*(a, b: StatusCode): bool {.borrow.}
proc `$`*(a: StatusCode): string {.borrow.}
# XXX grpcCancelled
const
  stcOk* = 0.StatusCode
  stcCancelled* = 1.StatusCode
  stcUnknown* = 2.StatusCode
  stcInvalidArg* = 3.StatusCode
  stcDeadlineEx* = 4.StatusCode
  stcNotFound* = 5.StatusCode
  stcAlreadyExists* = 6.StatusCode
  stcPermissionDenied* = 7.StatusCode
  stcResourceExhausted* = 8.StatusCode
  stcFailedPrecondition* = 9.StatusCode
  stcAborted* = 10.StatusCode
  stcOutOfRange* = 11.StatusCode
  stcUnimplemented* = 12.StatusCode
  stcInternal* = 13.StatusCode
  stcUnavailable* = 14.StatusCode
  stcDataLoss* = 15.StatusCode
  stcUnauthenticated* = 16.StatusCode

proc name*(code: StatusCode): string {.raises: [].} =
  result = case code:
  of stcOk: "OK"
  of stcCancelled: "CANCELLED"
  of stcUnknown: "UNKNOWN"
  of stcInvalidArg: "INVALID_ARGUMENT"
  of stcDeadlineEx: "DEADLINE_EXCEEDED"
  of stcNotFound: "NOT_FOUND"
  of stcAlreadyExists: "ALREADY_EXISTS"
  of stcPermissionDenied: "PERMISSION_DENIED"
  of stcResourceExhausted: "RESOURCE_EXHAUSTED"
  of stcFailedPrecondition: "FAILED_PRECONDITION"
  of stcAborted: "ABORTED"
  of stcOutOfRange: "OUT_OF_RANGE"
  of stcUnimplemented: "UNIMPLEMENTED"
  of stcInternal: "INTERNAL"
  of stcUnavailable: "UNAVAILABLE"
  of stcDataLoss: "DATA_LOSS"
  of stcUnauthenticated: "UNAUTHENTICATED"
  else: doAssert false; ""

func toStatusCode*(code: ErrorCode): StatusCode {.raises: [].} =
  case code
  of errNoError,
      errProtocolError,
      errInternalError,
      errFlowControlError,
      errSettingsTimeout,
      errFrameSizeError,
      errCompressionError,
      errConnectError:
    stcInternal
  of errRefusedStream:
    stcUnavailable
  of errCancel:
    stcCancelled
  of errEnhanceYourCalm:
    stcResourceExhausted
  of errInadequateSecurity:
    stcPermissionDenied
  #of errStreamClosed, errHttp11Required:
  else:
    stcUnknown
