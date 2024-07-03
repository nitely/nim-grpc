{.define: ssl.}

from std/os import getEnv
import std/asyncdispatch
import std/tables

import ../src/grpc/server
import ../src/grpc/utils

const localHost* = "127.0.0.1"
const localPort* = Port 4443
const certFile = getEnv "HYPERX_TEST_CERTFILE"
const keyFile = getEnv "HYPERX_TEST_KEYFILE"

importProto3("hello.proto")

proc sayHello(strm: GrpcStream) {.async.} =
  let request = await strm.recvMessage(HelloRequest)
  await strm.sendMessage(
    HelloReply(message: "Hello, " & request.name)
  )

when isMainModule:
  proc main() {.async.} =
    echo "Serving forever"
    let server = newServer()
    await server.serve({
      "/helloworld.Greeter/SayHello": sayHello.ViewCallback
    }.newtable)
  waitFor main()
  echo "ok"
