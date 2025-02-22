import std/asyncdispatch
import std/strbasics
import std/times
import std/monotimes

import pkg/hyperx/client
import pkg/hyperx/errors

import ./clientserver
import ./errors
import ./headers
import ./utils
import ./protobuf

export
  ClientContext,
  newClient,
  with,
  GrpcResponseError,
  `==`,
  recvMessage,
  sendMessage,
  sendEnd,
  sendCancel,
  whileRecvMessages,
  GrpcStream,
  newGrpcStream,
  headersOut,
  sendHeaders,
  GrpcTimeoutUnit,
  protobuf,
  trace

func timeoutMillis(strm: GrpcStream): int {.raises: [].} =
  template tt: untyped = strm.timeout
  case strm.timeoutUnit
  of grpcHour: tt * 3600000
  of grpcMinute: tt * 60000
  of grpcSecond: tt * 1000
  of grpcMsec: tt
  of grpcUsec: max(1, tt div 1000)
  of grpcNsec: max(1, tt div 1_000_000)

proc deadlineTask(strm: GrpcStream) {.async.} =
  ## Meant to be asyncCheck'd
  doAssert strm.timeout > 0
  let timeout = strm.timeoutMillis
  let ms = min(timeout, 1000)
  let deadline = getMonoTime()+initDuration(milliseconds=timeout)
  var timeLeft = inMilliseconds(deadline-getMonoTime())
  while timeLeft > 0 and not strm.ended:
    await sleepAsync(min(timeLeft, ms))
    timeLeft = inMilliseconds(deadline-getMonoTime())
  strm.deadlineEx = not strm.ended
  if strm.deadlineEx:
    await failSilently strm.sendCancel()

template with*(strm: GrpcStream, body: untyped): untyped =
  doAssert strm.typ == gtClient
  var failure = false
  var failureCode = grpcInternal
  var deadlineFut: Future[void] = nil
  if strm.timeout > 0:
    deadlineFut = deadlineTask(strm)
  try:
    with strm.stream:
      try:
        block:
          body
        check not strm.canceled, newGrpcFailure(grpcCancelled)
        if not strm.stream.sendEnded:
          await strm.sendEnd()
        if not strm.recvEnded:
          await strm.recvEnd()
      finally:
        strm.ended = true
        if strm.deadlineEx:
          await failSilently deadlineFut
        elif deadlineFut != nil:
          asyncCheck deadlineFut
        if not strm.canceled and not strm.recvEnded:
          await failSilently strm.sendCancel()
  except GrpcRemoteFailure:
    # grpc-go server sends Rst no_error but trailer status is ok
    debugErr getCurrentException()
    discard
  except GrpcFailure as err:
    debugErr err
    failure = true
    failureCode = err.code
  strm.headers[].add strm.stream.recvTrailers
  debugInfo strm.headers[]
  check not strm.deadlineEx, newGrpcFailure(grpcDeadlineEx)
  check not strm.canceled, newGrpcFailure(grpcCancelled)
  checkResponseError(strm.headers[])
  check not failure, newGrpcFailure(failureCode)
