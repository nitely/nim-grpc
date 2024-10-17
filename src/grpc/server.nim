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

type
  GrpcCallback* = proc(strm: GrpcStream) {.async.}
  GrpcRoutes* = TableRef[string, GrpcCallback]

func trailersOut*(strm: GrpcStream, status: StatusCode, msg = ""): Headers =
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
  tryHyperx await strm.stream.sendHeaders(headers2[], finish = true)

proc sendTrailers(strm: GrpcStream, status: StatusCode, msg = ""): Future[void] =
  strm.sendTrailers(strm.trailersOut(status, msg))

proc sendCancel*(strm: GrpcStream, status: StatusCode) {.async.} =
  await strm.sendTrailers(status)
  await strm.sendCancel()

proc deadlineTask(strm: GrpcStream, timeout: int) {.async.} =
  doAssert timeout > 0
  var timeLeft = timeout
  let ms = min(timeLeft, 1000)
  while timeLeft > 0 and not strm.ended:
    await sleepAsync(min(timeLeft, ms))
    timeLeft -= ms
  strm.deadlineEx = not strm.ended
  if strm.deadlineEx:
    if not strm.trailersSent:
      await failSilently strm.sendTrailers(stcDeadlineEx)
      await failSilently strm.sendCancel()

proc processStream(
  strm: GrpcStream, routes: GrpcRoutes
) {.async.} =
  with strm.stream:
    var deadlineFut: Future[void]
    try:
      await strm.recvHeaders()
      let reqHeaders = toRequestHeaders strm.headers[]
      strm.compress = reqHeaders.compress
      check reqHeaders.path in routes, newGrpcFailure stcNotFound
      if reqHeaders.timeout > 0:
        deadlineFut = deadlineTask(strm, reqHeaders.timeout)
      await routes[reqHeaders.path](strm)
      if not strm.recvEnded:
        await strm.recvEnd()
      if not strm.trailersSent:
        await strm.sendTrailers(stcOk)
        #await strm.sendNoError()
    except GrpcRemoteFailure as err:
      raise err
    except GrpcFailure as err:
      if not strm.trailersSent:
        await failSilently strm.sendTrailers(err.code, err.message)
        await failSilently strm.sendNoError()
      raise err
    except CatchableError as err:
      if not strm.trailersSent:
        await failSilently strm.sendTrailers(stcInternal)
        await failSilently strm.sendNoError()
      raise err
    finally:
      strm.ended = true
      if strm.deadlineEx:
        await failSilently deadlineFut
      elif deadlineFut != nil:
        asyncCheck deadlineFut

proc processStreamHandler(
  strm: GrpcStream,
  routes: GrpcRoutes
) {.async.} =
  try:
    await processStream(strm, routes)
  except GrpcFailure:
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg
  except CatchableError:
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg

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
  except CatchableError:
    debugInfo getCurrentException().getStackTrace()
    debugInfo getCurrentException().msg

proc serve*(server: ServerContext, routes: GrpcRoutes) {.async.} =
  with server:
    while server.isConnected:
      let client = await server.recvClient()
      asyncCheck processClientHandler(client, routes)
