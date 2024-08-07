
import std/asyncdispatch
import std/strbasics

import pkg/hyperx/client
import pkg/hyperx/errors

import ./errors
import ./utils

type Headers* = ref seq[(string, string)]
type GrpcTyp* = enum
  gtServer, gtClient
type GrpcTimeoutUnit* = enum
  grpcHour, grpcMinute, grpcSecond, grpcMsec, grpcUsec, grpcNsec
type GrpcStream* = ref object
  typ*: GrpcTyp
  stream*: ClientStream
  path*: ref string
  timeout*: int
  timeoutUnit*: GrpcTimeoutUnit
  compress*: bool
  headers*: ref string
  headersSent*: bool  # XXX state
  trailersSent*: bool  # XXX state
  canceled*: bool
  deadlineEx*: bool
  ended*: bool
  buff: ref string

proc newGrpcStream(
  typ: GrpcTyp,
  stream: ClientStream,
  path = "",
  timeout = 0,
  timeoutUnit = grpcMsec,
  compress = false
): GrpcStream =
  doAssert timeout < 100_000_000
  GrpcStream(
    typ: typ,
    stream: stream,
    path: newStringRef(path),
    compress: compress,
    timeout: timeout,
    timeoutUnit: timeoutUnit,
    headers: newStringRef(),
    buff: newStringRef()
  )

proc newGrpcStream*(stream: ClientStream): GrpcStream =
  ## Server stream
  newGrpcStream(gtServer, stream)

proc newGrpcStream*(
  client: ClientContext,
  path: string,
  timeout = 0,
  timeoutUnit = grpcMsec,
  compress = false
): GrpcStream =
  ## Client stream
  newGrpcStream(
    gtClient, newClientStream(client), path, timeout, timeoutUnit, compress
  )

proc recvEnded*(strm: GrpcStream): bool =
  result = strm.stream.recvEnded and strm.buff[].len == 0

proc recvHeaders*(strm: GrpcStream) {.async.} =
  doAssert strm.headers[].len == 0
  #check not strm.canceled, newGrpcFailure stcCancelled
  tryHyperx await strm.stream.recvHeaders(strm.headers)

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

proc recvMessage*(
  strm: GrpcStream, data: ref string
): Future[bool] {.async.} =
  ## Adds a single record to data. It will add nothing
  ## if recv ends.
  if strm.headers[].len == 0:
    await strm.recvHeaders()
  while not strm.stream.recvEnded and not strm.buff[].hasFullRecord:
    #check not strm.canceled, newGrpcFailure stcCancelled
    tryHyperx await strm.stream.recvBody(strm.buff)
  check strm.buff[].hasFullRecord or strm.buff[].len == 0
  let L = strm.buff[].recordSize
  data[].add toOpenArray(strm.buff[], 0, L-1)
  strm.buff[].setSlice L .. strm.buff[].len-1
  result = L > 0

func `$`(typ: GrpcTimeoutUnit): char =
  case typ
  of grpcHour: 'H'
  of grpcMinute: 'M'
  of grpcSecond: 'S'
  of grpcMsec: 'm'
  of grpcUsec: 'u'
  of grpcNsec: 'n'

func headersOut*(strm: GrpcStream): Headers {.raises: [].} =
  case strm.typ
  of gtClient:
    var headers = @[
      (":method", "POST"),
      (":scheme", "https"),
      (":path", strm.path[]),
      (":authority", strm.stream.client.hostname),
      ("te", "trailers"),
      ("grpc-accept-encoding", "identity, gzip, deflate"),
      ("user-agent", "grpc-nim/0.1.0"),
      ("content-type", "application/grpc+proto")
    ]
    if strm.compress:
      headers.add ("grpc-encoding", "gzip")
    if strm.timeout > 0:
      headers.add ("grpc-timeout", $strm.timeout & $strm.timeoutUnit)
    newSeqRef(headers)
  of gtServer:
    var headers = @[
      (":status", "200"),
      ("grpc-accept-encoding", "identity, gzip, deflate"),
      ("content-type", "application/grpc+proto")
    ]
    if strm.compress:
      headers.add ("grpc-encoding", "gzip")
    newSeqRef(headers)

proc sendHeaders*(strm: GrpcStream, headers: Headers) {.async.} =
  check not strm.deadlineEx, newGrpcFailure stcDeadlineEx
  check not strm.canceled, newGrpcFailure stcCancelled
  check not strm.headersSent
  strm.headersSent = true
  tryHyperx await strm.stream.sendHeaders(headers, finish = false)

proc sendHeaders*(strm: GrpcStream): Future[void] =
  strm.sendHeaders(strm.headersOut)

proc sendMessage*(
  strm: GrpcStream, data: ref string, finish = false
) {.async.} =
  if not strm.headersSent:
    await strm.sendHeaders()
  check not strm.deadlineEx, newGrpcFailure stcDeadlineEx
  check not strm.canceled, newGrpcFailure stcCancelled
  tryHyperx await strm.stream.sendBody(data, finish)

proc sendEnd*(strm: GrpcStream): Future[void] =
  strm.sendMessage(newStringRef(), finish = true)

proc sendCancel*(strm: GrpcStream) {.async.} =
  # XXX maybe just raise cancel error here
  strm.canceled = true
  tryHyperx await strm.stream.cancel(errCancel)

proc sendNoError*(strm: GrpcStream) {.async.} =
  tryHyperx await strm.stream.cancel(errNoError)

proc recvMessage*[T](strm: GrpcStream, t: typedesc[T]): Future[T] {.async.} =
  ## An error is raised if the stream recv ends without a message.
  ## This is common to end the stream.
  let msg = newStringRef()
  let recved = await strm.recvMessage(msg)
  check recved, newGrpcNoMessageException()
  result = msg.pbDecode(T)

proc recvMessage2*[T](strm: GrpcStream, t: typedesc[T]): Future[(bool, T)] {.async.} =
  ## Return true if message was compressed, otherwise return false.
  let msg = newStringRef()
  let recved = await strm.recvMessage(msg)
  check recved, newGrpcNoMessageException()
  result[0] = msg[][0] == 1.char
  result[1] = msg.pbDecode(T)

template whileRecvMessages*(strm: GrpcStream, body: untyped): untyped =
  try:
    while not strm.recvEnded:
      body
  except GrpcNoMessageException:
    doAssert strm.recvEnded

proc sendMessage*[T](
  strm: GrpcStream, msg: T, finish = false, compress = false
): Future[void] =
  if strm.typ == gtClient and compress:
    doAssert strm.compress, "stream compression is not enabled"
  let data = msg.pbEncode(compress and strm.compress)
  result = strm.sendMessage(data, finish = finish)

proc failSilently*(fut: Future[void]) {.async.} =
  try:
    if fut != nil:
      await fut
  except HyperxError, GrpcFailure:
    debugInfo getCurrentException().msg
    debugInfo getCurrentException().getStackTrace()
