import ./statuscodes
export statuscodes

type
  GrpcFailure* = object of CatchableError
    code*: StatusCode
    message*: string
  GrpcRemoteFailure* = object of GrpcFailure
  GrpcNoMessageException* = object of GrpcFailure
  GrpcResponseError* = object of GrpcRemoteFailure

func newGrpcFailure*(
  code: StatusCode, message = ""
): ref GrpcFailure {.raises: [].} =
  result = (ref GrpcFailure)(msg: code.name, code: code, message: message)

func newGrpcFailure*(): ref GrpcFailure {.raises: [].} =
  result = newGrpcFailure(stcInternal)

func newGrpcRemoteFailure*(
  code: StatusCode, message = ""
): ref GrpcRemoteFailure {.raises: [].} =
  result = (ref GrpcRemoteFailure)(msg: code.name, code: code, message: message)

func newGrpcNoMessageException*(): ref GrpcNoMessageException {.raises: [].} =
  result = (ref GrpcNoMessageException)(
    msg: stcInternal.name,
    code: stcInternal,
    message: "A message was expected"
  )

func newGrpcResponseError*(
  code: StatusCode, message: string
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: code.name, code: code, message: message)
