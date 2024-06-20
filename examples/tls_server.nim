{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/streams
import std/tables

import pkg/protobuf

import ../src/grpc/server
import ../src/grpc/utils

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

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

proc sayHello(strm: GrpcStream) {.async.} =
  let data = newStringRef()
  while not strm.recvEnded:  # XXX remove
    await strm.recvBody(data)
  let request = data[].decode().readHelloRequest()
  var name = ""
  if request.has(name):
    name = request.name
  let reply = new HelloReply
  reply.message = "Hello, " & name
  await strm.sendBody(newStringRef(encode(reply)), finish = false)

when isMainModule:
  proc main() {.async.} =
    echo "Serving forever"
    let server = newServer()
    await server.serve({
      "/helloworld.Greeter/SayHello": sayHello.ViewCallback
    }.newtable)
  waitFor main()
  echo "ok"
