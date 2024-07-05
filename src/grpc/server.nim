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
        ("grpc-encoding", "gzip"),  # XXX conf for identity
        #("grpc-accept-encoding", "identity, gzip, deflate"),
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
    except GrpcFailure as err:
      await failSilently strm.sendTrailers(err.code)
      raise err
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
    debugEcho err.msg
    debugEcho err.getStackTrace()

proc serve*(server: ServerContext, routes: GrpcRoutes) {.async.} =
  with server:
    while server.isConnected:
      let client = await server.recvClient()
      asyncCheck processClientHandler(client, routes)
