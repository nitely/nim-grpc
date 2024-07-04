
import std/asyncdispatch
import std/strbasics

import pkg/hyperx/client

import ./clientserver
import ./errors
import ./headers
import ./types
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
  GrpcStream,
  newGrpcStream,
  protobuf

proc sendHeaders(
  strm: ClientStream, path: ref string, contentLen = -1
) {.async.} =
  var headers = @[
    (":method", "POST"),
    (":scheme", "https"),
    (":path", path[]),
    (":authority", strm.client.hostname),
    ("te", "trailers"),
    ("grpc-encoding", "gzip"),  # XXX conf for identity
    ("grpc-accept-encoding", "identity, gzip, deflate"),
    ("user-agent", "grpc-nim/0.1.0"),
    ("content-type", "application/grpc+proto")
  ]
  if contentLen > -1:
    headers.add ("content-length", $contentLen)
  await strm.sendHeaders(
    newSeqRef(headers),
    finish = false
  )

template with*(strm: GrpcStream, body: untyped): untyped =
  var failure = false
  var sendFut, recvFut: Future[void]
  try:
    with strm.stream:
      recvFut = strm.stream.recvHeaders(strm.headers)
      sendFut = strm.stream.sendHeaders(strm.path)
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
    await failSilently(sendFut)
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
