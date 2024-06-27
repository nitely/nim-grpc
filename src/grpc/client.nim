{.define: ssl.}

import std/asyncdispatch
import std/strbasics

import pkg/hyperx/client

#import ./clientserver
import ./errors
import ./headers
import ./types
import ./utils

export
  ClientContext,
  newClient,
  with,
  GrpcResponseError,
  `==`

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
  headers: ref string
  buff: ref string

proc newGrpcStream*(client: ClientContext, path: ref string): GrpcStream =
  GrpcStream(
    stream: newClientStream(client),
    path: path,
    headers: newStringRef(),
    buff: newStringRef()
  )

proc recvEnded*(strm: GrpcStream): bool =
  result = strm.stream.recvEnded() and strm.buff[].len == 0

func recordSize(data: string): int =
  if data.len == 0:
    return 0
  doAssert data.len >= 5
  var L = 0'u32
  L += data[1].uint32 shl 24
  L += data[2].uint32 shl 16
  L += data[3].uint32 shl 8
  L += data[4].uint32
  # XXX check bit 31 is not set
  result = L.int+5

func hasFullRecord(data: string): bool =
  if data.len < 5:
    return false
  result = data.len >= data.recordSize

proc recvBody*(strm: GrpcStream, data: ref string) {.async.} =
  ## Adds a single record to data. It will add nothing
  ## if recv ends.
  while not strm.stream.recvEnded and not strm.buff[].hasFullRecord:
    await strm.stream.recvBody(strm.buff)
  check strm.buff[].hasFullRecord or strm.buff[].len == 0
  let L = strm.buff[].recordSize
  data[].add toOpenArray(strm.buff[], 0, L-1)
  strm.buff[].setSlice L .. strm.buff[].len-1

proc sendBody*(
  strm: GrpcStream,
  data: ref string,
  finish = false
) {.async.} =
  await strm.stream.sendBody(data, finish)

proc failSilently(fut: Future[void]) {.async.} =
  try:
    if fut != nil:
      await fut
  except HyperxError as err:
    debugEcho err.msg

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
        await strm.sendBody(newStringRef(), finish = true)
      if not strm.recvEnded:
        let recvData = newStringRef()
        await strm.recvBody(recvData)
        check recvData[].len == 0
        check strm.recvEnded
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

proc recvBodyFull(
  strm: GrpcStream,
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
    let recvFut = strm.recvBodyFull(result)
    try:
      await strm.sendBody(data, finish = true)
    finally:
      await recvFut
