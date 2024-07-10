import std/asyncdispatch
import std/tables

import pkg/hyperx/server

import ./clientserver
import ./errors
import ./headers
import ./utils
import ./protobuf

export
  ServerContext,
  newServer,
  recvMessage,
  sendMessage,
  sendEnd,
  whileRecvMessages,
  GrpcStream,
  headersOut,
  sendHeaders,
  protobuf

template with*(strm: GrpcStream, body: untyped): untyped =
  try:
    with strm.stream:
      block:
        body
      if not strm.stream.sendEnded:
        await strm.sendMessage(newStringRef(), finish = true)
      if not strm.recvEnded:
        let recvData = newStringRef()
        let recved = await strm.recvMessage(recvData)
        check recvData[].len == 0
        check strm.recvEnded
        check not recved
  except HyperxError:
    debugEcho getCurrentException().msg
    debugEcho getCurrentException().getStackTrace()
    raise newGrpcFailure()

type
  GrpcCallback* = proc(strm: GrpcStream) {.async.}
  GrpcRoutes* = TableRef[string, GrpcCallback]

func trailersOut*(strm: GrpcStream, status: StatusCode, msg = ""): Headers =
  result = newSeqRef[(string, string)]()
  result[].add ("grpc-status", $status)
  if msg.len > 0:
    result[].add ("grpc-message", msg)

proc sendTrailers*(strm: GrpcStream, headers: Headers) {.async.} =
  doAssert not strm.stream.sendEnded
  doAssert not strm.trailersSent
  strm.trailersSent = true
  if not strm.headersSent:
    await strm.sendHeaders()
  await strm.stream.sendHeaders(headers, finish = true)

proc sendTrailers(strm: GrpcStream, status: StatusCode, msg = "") {.async.} =
  await strm.sendTrailers(strm.trailersOut(status, msg))

proc processStream(
  strm: GrpcStream, routes: GrpcRoutes
) {.async.} =
  with strm:
    await strm.stream.recvHeaders(strm.headers)
    let reqHeaders = toRequestHeaders strm.headers[]
    if reqHeaders.path notin routes:
      # XXX send RST
      await strm.sendTrailers(stcNotFound)
      return
    try:
      await routes[reqHeaders.path](strm)
    except GrpcFailure as err:
      if not strm.trailersSent:
        await failSilently strm.sendTrailers(err.code, err.message)
      raise err
    except CatchableError as err:
      if not strm.trailersSent:
        await failSilently strm.sendTrailers(stcInternal)
      raise err
    if not strm.trailersSent:
      await strm.sendTrailers(stcOk)

proc processStreamHandler(
  strm: GrpcStream,
  routes: GrpcRoutes
) {.async.} =
  try:
    await processStream(strm, routes)
  except HyperxStrmError, HyperxConnError, GrpcFailure:
    debugEcho getCurrentException().getStackTrace()
    debugEcho getCurrentException().msg

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
    debugEcho err.getStackTrace()
    debugEcho err.msg

proc serve*(server: ServerContext, routes: GrpcRoutes) {.async.} =
  with server:
    while server.isConnected:
      let client = await server.recvClient()
      asyncCheck processClientHandler(client, routes)
