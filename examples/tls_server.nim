{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

import pkg/protobuf_serialization
import pkg/protobuf_serialization/proto_parser

import ../src/grpc/server
import ../src/grpc/utils

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

import_proto3("hello.proto")

proc sayHello(strm: GrpcStream) {.async.} =
  let data = newStringRef()
  while not strm.recvEnded:  # XXX remove
    await strm.recvBody(data)
  let request = data.pbDecode(HelloRequest)
  let reply = HelloReply(message: "Hello, " & request.name)
  await strm.sendBody(reply.pbEncode(), finish = false)

when isMainModule:
  proc main() {.async.} =
    echo "Serving forever"
    let server = newServer()
    await server.serve({
      "/helloworld.Greeter/SayHello": sayHello.ViewCallback
    }.newtable)
  waitFor main()
  echo "ok"
