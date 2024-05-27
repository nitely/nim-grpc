{.define: ssl.}

import std/asyncdispatch
import std/streams

import pkg/protobuf

import ../src/grpc/client

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

proc main() {.async.} =
  var client = newClient("127.0.0.1", Port 50051)
  withClient client:
    let request = new HelloRequest
    request.name = "you"
    let data = await client.get(
      newStringRef("/helloworld.Greeter/SayHello"),
      newStringRef(encode(request))
    )
    let reply = data[].decode().readHelloReply()
    if reply.has(message):
      echo reply.message

waitFor main()
