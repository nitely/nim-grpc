import ./statuscodes
export statuscodes

type
  GrpcError* = object of CatchableError
  GrpcFailure* = object of GrpcError
    code*: StatusCode
  GrpcNoMessageException* = object of GrpcFailure
  GrpcResponseError* = object of GrpcError
    code*: StatusCode

func newGrpcResponseError*(
  msg: string, code: StatusCode
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: msg, code: code)

func newGrpcFailure*(code: StatusCode): ref GrpcFailure {.raises: [].} =
  result = (ref GrpcFailure)(msg: code.name, code: code)

func newGrpcFailure*(): ref GrpcFailure {.raises: [].} =
  result = newGrpcFailure(stcInternal)

func newGrpcNoMessageException*(): ref GrpcNoMessageException {.raises: [].} =
  result = (ref GrpcNoMessageException)(
    msg: "A message was expected", code: stcInternal
  )
