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
  protobuf,
  trace

type
  GrpcCallback* = proc(strm: GrpcStream): Future[void] {.closure, gcsafe.}
  GrpcRoutes* = TableRef[string, GrpcCallback]

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
  tryHyperx await strm.stream.sendHeaders(headers2[], finish = true)

proc sendTrailers(strm: GrpcStream, status: GrpcStatusCode, msg = ""): Future[void] =
  strm.sendTrailers(strm.trailersOut(status, msg))

proc sendCancel*(strm: GrpcStream, status: GrpcStatusCode) {.async.} =
  await strm.sendTrailers(status)
  await failSilently strm.sendCancel()

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
      await failSilently strm.sendTrailers(grpcDeadlineEx)
      await failSilently strm.sendCancel()

proc processStream(
  strm: GrpcStream, routes: GrpcRoutes
) {.async.} =
  with strm.stream:
    var deadlineFut: Future[void] = nil
    try:
      await strm.recvHeaders()
      let reqHeaders = toRequestHeaders strm.headers[]
      strm.compress = reqHeaders.compress
      check reqHeaders.path in routes, newGrpcFailure grpcNotFound
      if reqHeaders.timeout > 0:
        deadlineFut = deadlineTask(strm, reqHeaders.timeout)
      await routes[reqHeaders.path](strm)
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
      await failSilently strm.sendNoError()
      strm.ended = true
      if strm.deadlineEx:
        await failSilently deadlineFut
      elif deadlineFut != nil:
        asyncCheck deadlineFut

proc processStreamWrap(routes: static[GrpcRoutes]): StreamCallback =
  proc processStream(strm: ClientStream) {.async, gcsafe.} =
    try:
      await processStream(newGrpcStream(strm), routes)
    except CatchableError:
      debugErr getCurrentException()

proc serve*(server: ServerContext, routes: static[GrpcRoutes]) {.async.} =
  server.serve(processStreamWrap(routes))
