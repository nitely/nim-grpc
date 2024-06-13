import std/asyncdispatch

import pkg/hyperx/client

import ./errors
import ./headers
import ./types

export
  ClientContext,
  newClient,
  withClient,
  GrpcResponseError

func newSeqRef[T](s: seq[T]): ref seq[T] =
  result = new(seq[T])
  result[] = s

func newStringRef(s = ""): ref string =
  new result
  result[] = s

proc sendHeaders(
  strm: ClientStream, path: ref string, contentLen = -1
) {.async.} =
  var headers = @[
    (":method", "POST"),
    (":scheme", "https"),
    (":path", path[]),
    (":authority", strm.client.hostname),
    ("te", "trailers"),
    ("grpc-encoding", "identity"),
    ("grpc-accept-encoding", "identity"),
    ("user-agent", "grpc-nim/0.1.0"),
    ("content-type", "application/grpc+proto")
  ]
  if contentLen > -1:
    headers.add ("content-length", $contentLen)
  await strm.sendHeaders(
    newSeqRef(headers),
    finish = false
  )

type GrpcStream* = ref object
  stream: ClientStream
  path: ref string

proc newGrpcStream*(client: ClientContext, path: ref string): GrpcStream =
  GrpcStream(
    stream: newClientStream(client),
    path: path
  )

proc failSilently(fut: Future[void]) {.async.} =
  try:
    if fut != nil:
      await fut
  except HyperxError as err:
    debugEcho err.msg

template with*(strm: GrpcStream, body: untyped) =
  let headersIn = newStringRef()
  var sendFut, recvFut: Future[void]
  try:
    withStream strm.stream:
      recvFut = strm.stream.recvHeaders(headersIn)
      sendFut = strm.stream.sendHeaders(strm.path)
      block:
        body
      # XXX cancel stream if not recvEnded, and error out
      # XXX send/recv trailers
      if not strm.stream.sendEnded:
        await strm.stream.sendBody(newStringRef(), finish = true)
  except HyperxError as err:
    debugEcho err.msg
  finally:
    await failSilently(recvFut)
    await failSilently(sendFut)
  #debugEcho headersIn[]
  # XXX remove if condition; parse trailers
  if not strm.stream.recvEnded:
    let respHeaders = toResponseHeaders headersIn[]
    if respHeaders.status != stcOk:
      raise newGrpcResponseError(
        respHeaders.statusMsg,
        respHeaders.status
      )

proc recvBodyFull(
  strm: ClientStream,
  data: ref string
) {.async.} =
  while not strm.recvEnded:
    await strm.recvBody(data)

proc get*(
  client: ClientContext,
  path, data: ref string
): Future[ref string] {.async.} =
  result = newStringRef()
  let strm = client.newGrpcStream(path)
  with strm:
    let recvFut = strm.stream.recvBodyFull(result)
    try:
      await strm.stream.sendBody(data, finish = true)
    finally:
      await recvFut
