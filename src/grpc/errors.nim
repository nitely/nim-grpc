import ./types

type
  GrpcError* = object of CatchableError
  GrpcFailure* = object of GrpcError
  GrpcNoMessageException* = object of GrpcFailure
  GrpcResponseError* = object of GrpcError
    code*: StatusCode

func newGrpcResponseError*(
  msg: string, code: StatusCode
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: msg, code: code)

func newGrpcFailure*(): ref GrpcFailure {.raises: [].} =
  result = (ref GrpcFailure)(msg: "Internal failure")

func newGrpcNoMessageException*(): ref GrpcNoMessageException {.raises: [].} =
  result = (ref GrpcNoMessageException)()
