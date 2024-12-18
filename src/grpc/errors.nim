import ./statuscodes
export statuscodes

type
  GrpcFailure* = object of CatchableError
    code*: GrpcStatusCode
    message*: string
  GrpcRemoteFailure* = object of GrpcFailure
  GrpcNoMessageException* = object of GrpcFailure
  GrpcResponseError* = object of GrpcRemoteFailure

func newGrpcFailure*(
  code: GrpcStatusCode, message = ""
): ref GrpcFailure {.raises: [].} =
  result = (ref GrpcFailure)(msg: code.name, code: code, message: message)

func newGrpcFailure*(): ref GrpcFailure {.raises: [].} =
  result = newGrpcFailure(grpcInternal)

func newGrpcRemoteFailure*(
  code: GrpcStatusCode, message = ""
): ref GrpcRemoteFailure {.raises: [].} =
  result = (ref GrpcRemoteFailure)(msg: code.name, code: code, message: message)

func newGrpcNoMessageException*(): ref GrpcNoMessageException {.raises: [].} =
  result = (ref GrpcNoMessageException)(
    msg: grpcInternal.name,
    code: grpcInternal,
    message: "A message was expected"
  )

func newGrpcResponseError*(
  code: GrpcStatusCode, message: string
): ref GrpcResponseError {.raises: [].} =
  result = (ref GrpcResponseError)(msg: code.name, code: code, message: message)
