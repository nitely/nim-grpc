import ./statuscodes
export statuscodes

type
  GrpcError* = object of CatchableError
  GrpcFailure* = object of GrpcError
    code*: StatusCode
    message*: string
  GrpcNoMessageException* = object of GrpcFailure
  GrpcResponseError* = object of GrpcError
    code*: StatusCode

func newGrpcResponseError*(
  code: StatusCode, msg: string
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: msg, code: code)

func newGrpcFailure*(
  code: StatusCode, message = ""
): ref GrpcFailure {.raises: [].} =
  result = (ref GrpcFailure)(msg: code.name, code: code, message: message)

func newGrpcFailure*(): ref GrpcFailure {.raises: [].} =
  result = newGrpcFailure(stcInternal)

func newGrpcNoMessageException*(): ref GrpcNoMessageException {.raises: [].} =
  result = (ref GrpcNoMessageException)(
    msg: stcInternal.name,
    code: stcInternal,
    message: "A message was expected"
  )
