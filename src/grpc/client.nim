import std/asyncdispatch
import std/strbasics

import pkg/hyperx/client

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
  whileRecvMessages,
  GrpcStream,
  newGrpcStream,
  protobuf

template with*(strm: GrpcStream, body: untyped): untyped =
  var failure = false
  var recvFut: Future[void]
  try:
    with strm.stream:
      # XXX remove; recvHeaders on recvMessage
      recvFut = strm.stream.recvHeaders(strm.headers)
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
  except HyperxError, GrpcFailure:
    #debugEcho err.msg
    failure = true
  finally:
    await failSilently(recvFut)
  strm.headers[].add strm.stream.recvTrailers
  #debugEcho strm.headers[]
  let respHeaders = toResponseHeaders strm.headers[]
  if respHeaders.status != stcOk:
    raise newGrpcResponseError(
      respHeaders.statusMsg,
      respHeaders.status
    )
  if failure:
    raise newGrpcFailure()
