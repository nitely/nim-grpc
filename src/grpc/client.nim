import std/asyncdispatch
import std/strbasics

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
  protobuf

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
  var timeLeft = strm.timeoutMillis()
  let ms = min(timeLeft, 1000)
  while timeLeft > 0 and not strm.ended:
    await sleepAsync(min(timeLeft, ms))
    timeLeft -= ms
  strm.deadlineEx = not strm.ended
  if strm.deadlineEx:
    if strm.headersSent:  # not idle; client only
      await failSilently strm.sendCancel()

template with*(strm: GrpcStream, body: untyped): untyped =
  doAssert strm.typ == gtClient
  var deadlineFut: Future[void]
  if strm.timeout > 0:
    deadlineFut = deadlineTask(strm)
  try:
    with strm.stream:
      body
  finally:
    strm.ended = true
    if strm.deadlineEx:
      await failSilently deadlineFut
    elif deadlineFut != nil:
      asyncCheck deadlineFut

template with2*(strm: GrpcStream, body: untyped): untyped =
  doAssert strm.typ == gtClient
  var failure = false
  var failureCode = stcInternal
  try:
    with strm.stream:
      var deadlineFut: Future[void]
      if strm.timeout > 0:
        deadlineFut = deadlineTask(strm)
      try:
        block:
          body
        # XXX cancel stream if not recvEnded, and error out
        # XXX send/recv trailers
        if strm.canceled:
          raise newGrpcFailure(stcCancelled)
        if not strm.stream.sendEnded:
          await strm.sendMessage(newStringRef(), finish = true)
        if not strm.recvEnded:
          let recvData = newStringRef()
          let recved = await strm.recvMessage(recvData)
          check recvData[].len == 0
          check strm.recvEnded
          check not recved
      finally:
        strm.ended = true
        if strm.deadlineEx:
          await failSilently deadlineFut
        elif deadlineFut != nil:
          asyncCheck deadlineFut
  except GrpcRemoteFailure:
    # grpc-go server sends Rst no_error but trailer status is ok
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg
    discard
  except GrpcFailure as err:
    debugInfo err.getStackTrace()
    debugInfo err.msg
    if strm.deadlineEx:
      raise newGrpcFailure(stcDeadlineEx)
    if strm.canceled:
      raise err
    failure = true
    failureCode = err.code
  except HyperxError:
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg
    doAssert false
  strm.headers[].add strm.stream.recvTrailers
  debugInfo strm.headers[]
  let respHeaders = toResponseHeaders strm.headers[]
  if respHeaders.status != stcOk:
    raise newGrpcResponseError(
      respHeaders.status,
      respHeaders.statusMsg
    )
  if failure:
    raise newGrpcFailure(failureCode)
