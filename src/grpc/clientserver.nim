
import std/asyncdispatch

import pkg/hyperx/client
import pkg/hyperx/errors

import ./errors
import ./utils

type Buff = object
  s: ref seq[byte]
  pos: int

template data(buff: Buff): untyped =
  toOpenArray(buff.s[], buff.pos, len(buff.s[])-1)

func len(buff: Buff): int {.inline.} =
  buff.s[].len-buff.pos

func truncate(buff: var Buff) =
  ## Drop the consumed bytes, keep the rest
  let L = buff.len
  if L > 0:
    moveMem(addr buff.s[][0], addr buff.s[][buff.pos], L)
  buff.s[].setLen L
  buff.pos = 0

type Headers* = ref seq[(string, string)]
type GrpcTimeoutUnit* = enum
  grpcHour, grpcMinute, grpcSecond, grpcMsec, grpcUsec, grpcNsec
type GrpcStreamBase* = ref object of RootObj
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
  buff: Buff
type GrpcStream* = ref object of GrpcStreamBase
  ## Server stream
type GrpcClientStream* = ref object of GrpcStreamBase
  ## Client stream

proc newGrpcStream*(stream: ClientStream): GrpcStream =
  ## Server stream
  GrpcStream(
    stream: stream,
    path: grpcNewStringRef(),
    headers: grpcNewStringRef(),
    buff: Buff(s: grpcNewSeqRef[byte](), pos: 0)
  )

proc newGrpcStream*(
  client: ClientContext,
  path: string,
  timeout = 0,
  timeoutUnit = grpcMsec,
  compress = false
): GrpcClientStream =
  ## Client stream
  doAssert timeout < 100_000_000
  GrpcClientStream(
    stream: newClientStream(client),
    path: grpcNewStringRef(path),
    compress: compress,
    timeout: timeout,
    timeoutUnit: timeoutUnit,
    headers: grpcNewStringRef(),
    buff: Buff(s: grpcNewSeqRef[byte](), pos: 0)
  )

func `$`(typ: GrpcTimeoutUnit): char =
  case typ
  of grpcHour: 'H'
  of grpcMinute: 'M'
  of grpcSecond: 'S'
  of grpcMsec: 'm'
  of grpcUsec: 'u'
  of grpcNsec: 'n'

func headersOut*(strm: GrpcStreamBase): Headers {.raises: [].} =
  var headers = newSeqOfCap[(string, string)](16)
  if strm of GrpcClientStream:
    headers.add (":method", "POST")
    headers.add (":scheme", "https")
    headers.add (":path", strm.path[])
    headers.add (":authority", strm.stream.client.hostname)
    headers.add ("te", "trailers")
    headers.add ("grpc-accept-encoding", "identity, gzip, deflate")
    headers.add ("user-agent", "grpc-nim/0.1.0")
    headers.add ("content-type", "application/grpc+proto")
    if strm.compress:
      headers.add ("grpc-encoding", "gzip")
    if strm.timeout > 0:
      headers.add ("grpc-timeout", $strm.timeout & $strm.timeoutUnit)
  else:
    headers.add (":status", "200")
    headers.add ("grpc-accept-encoding", "identity, gzip, deflate")
    headers.add ("content-type", "application/grpc+proto")
    if strm.compress:
      headers.add ("grpc-encoding", "gzip")
  return grpcNewSeqRef(headers)

proc sendHeaders*(strm: GrpcStreamBase, headers: Headers) {.async.} =
  grpcCheck not strm.deadlineEx, newGrpcFailure grpcDeadlineEx
  grpcCheck not strm.canceled, newGrpcFailure grpcCancelled
  grpcCheck not strm.headersSent
  strm.headersSent = true
  grpcCatchHyperx await strm.stream.sendHeaders(headers[], finish = false)

proc sendHeaders*(strm: GrpcStreamBase): Future[void] =
  strm.sendHeaders(strm.headersOut)

proc sendMessageImpl(
  strm: GrpcStreamBase, data: ref seq[byte], finish: bool
) {.async.} =
  if not strm.headersSent:
    await strm.sendHeaders()
  grpcCheck not strm.deadlineEx, newGrpcFailure grpcDeadlineEx
  grpcCheck not strm.canceled, newGrpcFailure grpcCancelled
  grpcCatchHyperx await strm.stream.sendBody(data, finish)

proc sendMessage*(strm: GrpcStream, data: ref seq[byte]): Future[void] =
  ## There is no finish; the server trailers end the stream
  strm.sendMessageImpl(data, finish = false)

proc sendMessage*(
  strm: GrpcClientStream, data: ref seq[byte], finish = false
): Future[void] =
  strm.sendMessageImpl(data, finish)

proc sendMessage*[T](
  strm: GrpcStream, msg: T, compress = false
): Future[void] =
  ## There is no finish; the server trailers end the stream
  let data = grpcPbEncode(msg, compress and strm.compress)
  result = strm.sendMessage(data)

proc sendMessage*[T](
  strm: GrpcClientStream, msg: T, finish = false, compress = false
): Future[void] =
  if compress:
    doAssert strm.compress, "stream compression is not enabled"
  let data = grpcPbEncode(msg, compress and strm.compress)
  result = strm.sendMessage(data, finish = finish)

proc sendEnd*(strm: GrpcClientStream): Future[void] =
  strm.sendMessage(grpcNewSeqRef[byte](), finish = true)

proc sendCancel*(strm: GrpcStreamBase) {.async.} =
  # XXX maybe just raise cancel error here
  strm.canceled = true
  grpcCatchHyperx await strm.stream.cancel(hyxCancel)

proc sendNoError*(strm: GrpcStream) {.async.} =
  grpcCatchHyperx await strm.stream.cancel(hyxNoError)

proc isRecvEmpty*(strm: GrpcStreamBase): bool =
  ## Return whether there is data left in the buffer.
  ## Even if true, recv may not have ended.
  result = strm.buff.len == 0

proc recvEnded*(strm: GrpcStreamBase): bool =
  result = strm.stream.recvEnded and strm.buff.len == 0

proc recvHeaders*(strm: GrpcStreamBase) {.async.} =
  doAssert strm.headers[].len == 0
  #check not strm.canceled, newGrpcFailure grpcCancelled
  let headers = grpcNewSeqRef[byte]()
  grpcCatchHyperx await strm.stream.recvHeaders(headers)
  strm.headers[].add headers[].toString

func recordSize(data: openArray[byte]): int =
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

func hasFullRecord(data: openArray[byte]): bool =
  if data.len < 5:
    return false
  result = data.len >= data.recordSize

proc recvMessage*(
  strm: GrpcStreamBase, data: ref seq[byte]
): Future[bool] {.async.} =
  ## Adds a single record to data. It will add nothing
  ## if recv ends.
  if not strm.headersSent and strm of GrpcClientStream:
    await strm.sendHeaders(strm.headersOut)
  if strm.headers[].len == 0:
    await strm.recvHeaders()
  while not strm.stream.recvEnded and not strm.buff.data.hasFullRecord:
    #check not strm.canceled, newGrpcFailure grpcCancelled
    grpcCatchHyperx await strm.stream.recvBody(strm.buff.s)
  grpcCheck strm.buff.data.hasFullRecord or strm.buff.len == 0
  let L = strm.buff.data.recordSize
  data[].add2 toOpenArray(strm.buff.data, 0, L-1)
  strm.buff.pos += L
  if not strm.buff.data.hasFullRecord:
    strm.buff.truncate()
  result = L > 0

proc recvMessage*[T](strm: GrpcStreamBase, t: typedesc[T]): Future[T] {.async.} =
  ## An error is raised if the stream recv ends without a message.
  ## This is common to end the stream.
  let msg = grpcNewSeqRef[byte]()
  let recved = await strm.recvMessage(msg)
  grpcCheck recved, newGrpcNoMessageException()
  result = grpcPbDecode(msg, T)

proc recvMessage2*[T](strm: GrpcStreamBase, t: typedesc[T]): Future[(bool, T)] {.async.} =
  ## Return true if message was compressed, otherwise return false.
  let msg = grpcNewSeqRef[byte]()
  let recved = await strm.recvMessage(msg)
  grpcCheck recved, newGrpcNoMessageException()
  result[0] = msg[][0] == 1
  result[1] = grpcPbDecode(msg, T)

proc recvEnd*(strm: GrpcStreamBase) {.async.} =
  let recvData = grpcNewSeqRef[byte]()
  let recved = await strm.recvMessage(recvData)
  grpcCheck recvData[].len == 0
  grpcCheck strm.recvEnded
  grpcCheck not recved

template whileRecvMessages*(strm: GrpcStreamBase, body: untyped): untyped =
  try:
    while not strm.recvEnded:
      body
  except GrpcNoMessageException:
    doAssert strm.recvEnded

proc failSilently*(fut: Future[void]) {.async.} =
  try:
    if fut != nil:
      await fut
  except HyperxError, GrpcFailure:
    grpcDebugErr getCurrentException()

proc testBuffAll*(strm: GrpcStreamBase) {.async.} =
  ## for testing purposes; buff all recv data
  if strm.headers[].len == 0:
    await strm.recvHeaders()
  while not strm.stream.recvEnded:
    grpcCatchHyperx await strm.stream.recvBody(strm.buff.s)
