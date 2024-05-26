import ./types

type
  GrpcError* = object of CatchableError
  GrpcResponseError* = object of GrpcError
    code*: StatusCode

func newGrpcResponseError*(
  msg: string, code: StatusCode
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: msg, code: code)
