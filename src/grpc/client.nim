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

# XXX no API should raise hyperx errors
template with*(strm: GrpcStream, body: untyped): untyped =
  doAssert strm.typ == gtClient
  var failure = false
  var failureCode = stcInternal
  try:
    with strm.stream:
      block:
        body
      # XXX cancel stream if not recvEnded, and error out
      # XXX send/recv trailers
      if not strm.stream.sendEnded:
        await strm.sendMessage(newStringRef(), finish = true)
      if not strm.recvEnded:
        let recvData = newStringRef()
        let recved = await strm.recvMessage(recvData)
        check recvData[].len == 0
        check strm.recvEnded
        check not recved
  except GrpcFailure as err:
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
