
type StatusCode* = distinct uint8
proc `==`*(a, b: StatusCode): bool {.borrow.}
proc `$`*(a: StatusCode): string {.borrow.}
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
