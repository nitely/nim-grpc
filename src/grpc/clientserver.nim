
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
  headers*: ref string
  headersSent*: bool  # XXX state
  trailersSent*: bool  # XXX state
  buff: ref string

proc newGrpcStream(
  typ: GrpcTyp,
  stream: ClientStream,
  path = "",
  timeout = 0,
  timeoutUnit = grpcMsec
): GrpcStream =
  doAssert timeout < 100_000_000
  GrpcStream(
    typ: typ,
    stream: stream,
    path: newStringRef(path),
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
  timeoutUnit = grpcMsec
): GrpcStream =
  ## Client stream
  newGrpcStream(
    gtClient, newClientStream(client), path, timeout, timeoutUnit
  )

proc recvEnded*(strm: GrpcStream): bool =
  result = strm.stream.recvEnded and strm.buff[].len == 0

proc recvHeaders*(strm: GrpcStream) {.async.} =
  doAssert strm.headers[].len == 0
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
  of grpcMsec: 's'
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
      ("grpc-encoding", "gzip"),  # XXX conf for identity
      ("grpc-accept-encoding", "identity, gzip, deflate"),
      ("user-agent", "grpc-nim/0.1.0"),
      ("content-type", "application/grpc+proto")
    ]
    if strm.timeout > 0:
      headers.add ("grpc-timeout", $strm.timeout & ' ' & $strm.timeoutUnit)
    newSeqRef(headers)
  of gtServer:
    newSeqRef(@[
      (":status", "200"),
      ("grpc-encoding", "gzip"),  # XXX conf for identity
      #("grpc-accept-encoding", "identity, gzip, deflate"),
      ("content-type", "application/grpc+proto")
    ])

proc sendHeaders*(strm: GrpcStream, headers: Headers) {.async.} =
  doAssert not strm.headersSent
  strm.headersSent = true
  tryHyperx await strm.stream.sendHeaders(headers, finish = false)

proc sendHeaders*(strm: GrpcStream) {.async.} =
  await strm.sendHeaders(strm.headersOut)

proc sendMessage*(
  strm: GrpcStream, data: ref string, finish = false
) {.async.} =
  doAssert not strm.stream.sendEnded
  if not strm.headersSent:
    await strm.sendHeaders()
  tryHyperx await strm.stream.sendBody(data, finish)

proc sendCancel*(strm: GrpcStream) {.async.} =
  tryHyperx await strm.stream.sendRst(errCancel)

proc sendNoError*(strm: GrpcStream) {.async.} =
  tryHyperx await strm.stream.sendRst(errNoError)

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
) {.async.} =
  await strm.sendMessage(msg.pbEncode(compress), finish = finish)

proc sendEnd*(strm: GrpcStream) {.async.} =
  doAssert not strm.stream.sendEnded
  await strm.sendMessage(newStringRef(), finish = true)

proc failSilently*(fut: Future[void]) {.async.} =
  try:
    if fut != nil:
      await fut
  except HyperxError, GrpcFailure:
    debugInfo getCurrentException().msg
    debugInfo getCurrentException().getStackTrace()
