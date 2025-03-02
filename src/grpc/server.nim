import std/asyncdispatch
import std/tables
import std/times
import std/monotimes

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
  protobuf,
  trace

type
  GrpcCallback* = proc(strm: GrpcStream): Future[void] {.closure, gcsafe.}
  GrpcRoutes* = TableRef[string, GrpcCallback]
  GrpcRoutes2* = seq[(string, GrpcCallback)]
  GrpcSafeCallback* = proc(strm: GrpcStream): Future[void] {.nimcall, gcsafe.}
  GrpcSafeRoutes* = seq[(string, GrpcSafeCallback)]
  GrpcSafeRoutes2 = ptr Table[string, GrpcSafeCallback]

func trailersOut*(strm: GrpcStream, status: GrpcStatusCode, msg = ""): Headers =
  result = newSeqRef[(string, string)]()
  result[].add ("grpc-status", $status)
  if msg.len > 0:
    result[].add ("grpc-message", percentEnc msg)

proc sendTrailers*(strm: GrpcStream, headers: Headers) {.async.} =
  doAssert strm.typ == gtServer
  check not strm.stream.sendEnded
  check not strm.trailersSent
  strm.trailersSent = true
  var headers2 = headers
  if not strm.headersSent:
    strm.headersSent = true
    headers2 = strm.headersOut()
    headers2[].add headers[]
  catchHyperx await strm.stream.sendHeaders(headers2[], finish = true)

proc sendTrailers(strm: GrpcStream, status: GrpcStatusCode, msg = ""): Future[void] =
  strm.sendTrailers(strm.trailersOut(status, msg))

proc sendCancel*(strm: GrpcStream, status: GrpcStatusCode) {.async.} =
  await strm.sendTrailers(status)
  await failSilently strm.sendCancel()

proc deadlineTask(strm: GrpcStream, timeout: int) {.async.} =
  doAssert timeout > 0
  let ms = min(timeout, 100)
  let deadline = getMonoTime()+initDuration(milliseconds = timeout)
  var timeLeft = timeout
  while timeLeft > 0 and not strm.ended:
    await sleepAsync(min(timeLeft, ms))
    timeLeft = min(timeLeft-ms, inMilliseconds(deadline-getMonoTime()).int)
  strm.deadlineEx = not strm.ended
  if strm.deadlineEx:
    if not strm.trailersSent:
      await failSilently strm.sendTrailers(grpcDeadlineEx)
      await failSilently strm.sendCancel()

proc processStream(
  strm: GrpcStream, routes: GrpcRoutes | GrpcSafeRoutes2
) {.async.} =
  var deadlineFut: Future[void] = nil
  try:
    await strm.recvHeaders()
    let reqHeaders = toRequestHeaders strm.headers[]
    strm.compress = reqHeaders.compress
    check reqHeaders.path in routes[], newGrpcFailure grpcNotFound
    if reqHeaders.timeout > 0:
      deadlineFut = deadlineTask(strm, reqHeaders.timeout)
    await routes[][reqHeaders.path](strm)
    check strm.isRecvEmpty() or strm.canceled, newGrpcFailure grpcInternal
    if not strm.trailersSent:
      await strm.sendTrailers(grpcOk)
  except GrpcRemoteFailure as err:
    raise err
  except GrpcFailure as err:
    if not strm.trailersSent:
      await failSilently strm.sendTrailers(err.code, err.message)
    raise err
  except CatchableError as err:
    if not strm.trailersSent:
      await failSilently strm.sendTrailers(grpcInternal)
    raise err
  finally:
    #await failSilently strm.sendNoError()
    strm.ended = true
    if strm.deadlineEx:
      await failSilently deadlineFut
    elif deadlineFut != nil:
      asyncCheck deadlineFut
      deadlineFut = nil

proc processStream(
  strm: ClientStream, routes: GrpcRoutes | GrpcSafeRoutes2
) {.async.} =
  try:
    await processStream(newGrpcStream(strm), routes)
  except CatchableError:
    debugErr getCurrentException()

proc processStreamWrap(routes: GrpcRoutes): StreamCallback =
  proc(strm: ClientStream): Future[void] {.closure, gcsafe.} =
    processStream(strm, routes)

proc serve*(server: ServerContext, routes: GrpcRoutes) {.async, gcsafe.} =
  await server.serve(processStreamWrap(routes))

proc serve*(server: ServerContext, routes: GrpcRoutes2) {.async, gcsafe.} =
  await server.serve(newTable(routes))

proc processStreamWrap(routes: static[GrpcSafeRoutes]): SafeStreamCallback =
  proc(strm: ClientStream): Future[void] {.nimcall, gcsafe.} =
    const routes2 = routes.toTable
    return processStream(strm, addr routes2)

const defaultMaxConns = int.high

proc run*(
  hostname: string,
  port: Port,
  routes: static[GrpcSafeRoutes],
  sslCertFile = "",
  sslKeyFile = "",
  maxConnections = defaultMaxConns,
  threads = 1,
  ssl: static[bool] = true
) =
  run(
    hostname,
    port,
    processStreamWrap(routes),
    sslCertFile,
    sslKeyFile,
    maxConnections,
    threads,
    ssl
  )
