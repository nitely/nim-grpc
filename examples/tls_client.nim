{.define: ssl.}

import std/asyncdispatch
import std/streams

import pkg/hyperx/client
import pkg/hyperx/utils
import pkg/protobuf

const protoDef = """
syntax = "proto3";

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
"""
parseProto(protoDef)

func newSeqRef[T](s: seq[T]): ref seq[T] =
  result = new(seq[T])
  result[] = s

func newStringRef(s = ""): ref string =
  new result
  result[] = s

func add(s: var string, ss: openArray[char]) {.raises: [].} =
  let L = s.len
  s.setLen(L+ss.len)
  for i in 0 .. ss.len-1:
    s[L+i] = ss[i]

iterator headersIt(s: string): (Slice[int], Slice[int]) {.inline.} =
  let L = s.len
  var na = 0
  var nb = 0
  var va = 0
  var vb = 0
  while na < L:
    nb = na
    nb += int(s[na] == ':')  # pseudo-header
    nb = find(s, ':', nb)
    doAssert nb != -1
    assert s[nb] == ':'
    assert s[nb+1] == ' '
    va = nb+2  # skip :\s
    vb = find(s, '\r', va)
    doAssert vb != -1
    assert s[vb] == '\r'
    assert s[vb+1] == '\n'
    yield (na .. nb-1, va .. vb-1)
    doAssert vb+2 > na
    na = vb+2  # skip /r/n

type StatusCode = distinct uint8
const
  stcOk = 0.StatusCode
  stcCancelled = 1.StatusCode
  stcUnknown = 2.StatusCode
  stcInvalidArg = 3.StatusCode
  stcDeadlineEx = 4.StatusCode
  stcNotFound = 5.StatusCode
  stcAlreadyExists = 6.StatusCode
  stcPermissionDenied = 7.StatusCode
  stcResourceExhausted = 8.StatusCode
  stcFailedPrecondition = 9.StatusCode
  stcAborted = 10.StatusCode
  stcOutOfRange = 11.StatusCode
  stcUnimplemented = 12.StatusCode
  stcInternal = 13.StatusCode
  stcUnavailable = 14.StatusCode
  stcDataLoss = 15.StatusCode
  stcUnauthenticated = 16.StatusCode
  stcBadStatusCode = 0xfe.StatusCode

func parseStatusCode(raw: openArray[char]): StatusCode =
  if raw.len notin 1 .. 2:
    return stcBadStatusCode
  for x in raw:
    if x.ord notin '0'.ord .. '9'.ord:
      return stcBadStatusCode
  var code = raw[0].ord - '0'.ord
  if raw.len > 1:
    code = code * 10 + (raw[1].ord - '0'.ord)
  if code > 16:
    return stcBadStatusCode
  return code.StatusCode

type ResponseHeaders = ref object
  status: StatusCode
  statusMsg: string

func newResponseHeaders(): ResponseHeaders =
  ResponseHeaders(
    status: stcOk,
    statusMsg: ""
  )

func toResponseHeaders(s: string): ResponseHeaders =
  result = newResponseHeaders()
  for (nn, vv) in headersIt s:
    if toOpenArray(s, nn.a, nn.b) == "grpc-status":
      result.status = parseStatusCode toOpenArray(s, vv.a, vv.b)
    elif toOpenArray(s, nn.a, nn.b) == "grpc-message":
      result.statusMsg = s[vv]

func toWireData(msg: string): string =
  template ones(n: untyped): uint = (1.uint shl n) - 1
  let L = msg.len.uint
  result = newStringOfCap(msg.len+5)
  result.setLen 5
  result[0] = 0.char  # uncompressed
  result[1] = ((L shr 24) and 8.ones).char
  result[2] = ((L shr 16) and 8.ones).char
  result[3] = ((L shr 8) and 8.ones).char
  result[4] = (L and 8.ones).char
  result.add msg

proc encode[T](s: T): string =
  var ss = newStringStream()
  ss.write s
  ss.setPosition 0
  result = ss.readAll.toWireData

func fromWireData(data: string): string =
  doAssert data.len >= 5
  doAssert data[0] == 0.char  # XXX uncompress
  result = newStringOfCap(data.len-5)
  result.add toOpenArray(data, 5, data.len-1)

proc decode(s: string): StringStream =
  result = newStringStream()
  result.write fromWireData(s)
  result.setPosition(0)

proc recv(
  strm: ClientStream,
  headers, data: ref string
) {.async.} =
  await strm.recvHeaders(headers)
  while not strm.recvEnded:
    await strm.recvBody(data)

proc send(
  strm: ClientStream,
  data: ref string
) {.async.} =
  await strm.sendHeaders(
    newSeqRef(@[
      (":method", "POST"),
      (":scheme", "https"),
      (":path", "/helloworld.Greeter/SayHello"),
      (":authority", "localhost"),
      ("te", "trailers"),
      ("grpc-encoding", "identity"),
      ("grpc-accept-encoding", "identity"),
      ("user-agent", "grpc-nim/0.1.0"),
      ("content-type", "application/grpc+proto"),
      ("content-length", $data[].len)
    ]),
    finish = false
  )
  await strm.sendBody(data, finish = true)

proc main() {.async.} =
  var client = newClient("127.0.0.1", Port 50051)
  withClient client:
    let strm = client.newClientStream()
    withStream strm:
      # start recv before send in case of error
      let headersIn = newStringRef()
      let dataIn = newStringRef()
      let recvFut = strm.recv(headersIn, dataIn)
      let msg = new HelloRequest
      msg.name = "you"
      let dataOut = newStringRef(encode(msg))
      let sendFut = strm.send(dataOut)
      var connErr: ref HyperxConnError = nil
      var strmErr: ref HyperxStrmError = nil
      try:
        await sendFut
      except HyperxStrmError as err:
        debugEcho err.msg
        strmErr = err
      except HyperxConnError as err:
        debugEcho err.msg
        connErr = err
      try:
        await recvFut
      except HyperxStrmError as err:
        debugEcho err.msg
        strmErr = err
      except HyperxConnError as err:
        debugEcho err.msg
        connErr = err
      echo headersIn[]
      let respHeaders = toResponseHeaders headersIn[]
      echo respHeaders.repr
      if connErr != nil:
        raise (ref HyperxConnError)(msg: connErr.msg)
      if strmErr != nil:
        raise (ref HyperxStrmError)(msg: strmErr.msg)
      if dataIn[].len > 0:
        let readMsg = dataIn[].decode().readHelloRequest()
        if readMsg.has(name):
          echo readMsg.name

waitFor main()
