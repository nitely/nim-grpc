{.define: ssl.}

import std/asyncdispatch
import std/streams

import pkg/hyperx/client
import pkg/protobuf

import ../src/grpc/errors
import ../src/grpc/headers
import ../src/grpc/types

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
      if respHeaders.status != stcOk:
        raise newGrpcResponseError(
          respHeaders.statusMsg,
          respHeaders.status
        )
      if connErr != nil:
        raise (ref HyperxConnError)(msg: connErr.msg)
      if strmErr != nil:
        raise (ref HyperxStrmError)(msg: strmErr.msg)
      if dataIn[].len > 0:
        let readMsg = dataIn[].decode().readHelloRequest()
        if readMsg.has(name):
          echo readMsg.name

waitFor main()
