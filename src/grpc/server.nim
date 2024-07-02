{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables
import std/strbasics

import pkg/protobuf
import pkg/hyperx/server

import ./errors
import ./types
import ./headers
import ./utils

export
  ServerContext

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

type
  GrpcStream* = ref object
    stream: ClientStream
    headers: ref string
    buff: ref string

proc newGrpcStream*(strm: ClientStream): GrpcStream =
  GrpcStream(
    stream: strm,
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
    debugEcho err.getStackTrace()

template with*(strm: GrpcStream, body: untyped): untyped =
  var failure = false
  try:
    with strm.stream:
      block:
        body
      if not strm.stream.sendEnded:
        await strm.sendBody(newStringRef(), finish = true)
      if not strm.recvEnded:
        let recvData = newStringRef()
        await strm.recvBody(recvData)
        check recvData[].len == 0
        check strm.recvEnded
  except HyperxError, GrpcFailure:
    debugEcho getCurrentException().msg
    debugEcho getCurrentException().getStackTrace()
    failure = true
  if failure:
    raise newGrpcFailure()

type
  ViewCallback* = proc(strm: GrpcStream) {.async.}
  GrpcRoutes* = TableRef[string, ViewCallback]

proc sendTrailers(strm: GrpcStream, status: StatusCode) {.async.} =
  doAssert not strm.stream.sendEnded
  await strm.stream.sendHeaders(
    newSeqRef(@[("grpc-status", $status)]),
    finish = true
  )

proc processStream(
  strm: GrpcStream, routes: GrpcRoutes
) {.async.} =
  with strm:
    let data = newStringRef()
    await strm.stream.recvHeaders(data)
    await strm.stream.sendHeaders(
      newSeqRef(@[
        (":status", "200"),
        ("grpc-encoding", "identity"),
        ("grpc-accept-encoding", "identity"),
        ("content-type", "application/grpc+proto")
      ]),
      finish = false
    )
    let reqHeaders = toRequestHeaders data[]
    if reqHeaders.path notin routes:
      # XXX send RST
      await strm.sendTrailers(stcNotFound)
      return
    try:
      await routes[reqHeaders.path](strm)
    except CatchableError as err:
      await failSilently strm.sendTrailers(stcInternal)
      raise err
    await strm.sendTrailers(stcOk)

proc processStreamHandler(
  strm: GrpcStream,
  routes: GrpcRoutes
) {.async.} =
  try:
    await processStream(strm, routes)
  except HyperxStrmError as err:
    debugEcho err.msg
    debugEcho err.getStackTrace()
  except HyperxConnError as err:
    debugEcho err.msg
    debugEcho err.getStackTrace()

proc processClient(
  client: ClientContext,
  routes: GrpcRoutes
) {.async.} =
  with client:
    while client.isConnected:
      let strm = await client.recvStream()
      asyncCheck processStreamHandler(newGrpcStream(strm), routes)

proc processClientHandler(
  client: ClientContext,
  routes: GrpcRoutes
) {.async.} =
  try:
    await processClient(client, routes)
  except HyperxConnError as err:
    debugEcho err.msg
    debugEcho err.getStackTrace()

proc serve*(server: ServerContext, routes: GrpcRoutes) {.async.} =
  with server:
    while server.isConnected:
      let client = await server.recvClient()
      asyncCheck processClientHandler(client, routes)

proc newServer*(): ServerContext =
  newServer(
    localHost, localPort, certFile, keyFile
  )
